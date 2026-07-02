"""Pytest fixtures + helpers for the container promotion gate.

The gate tests an exact candidate image *by digest*: the workflow sets
GATE_IMAGE_<MODEL>=ghcr.io/owner/image@sha256:... for the model under test, and
the suite tests that exact ref (no rebuild between test and promotion). Locally,
with no override, it tests `:latest`.
"""
from __future__ import annotations
import json
import os
import pathlib
import subprocess

import pytest
import yaml

REPO = pathlib.Path(__file__).resolve().parents[1]


def load_json(p):
    with open(p) as f:
        return json.load(f)


def config():
    """Per-model test config, read directly from the canonical models.yml.

    models.yml is the single owner of this data (step 3 of the config migration:
    the old hand-maintained tests/test_config.json was deleted rather than
    generated — no mirrored artifact, no drift surface). The adapter keeps the
    shape the tests were written against.
    """
    manifest = yaml.safe_load((REPO / "models.yml").read_text())
    shared_base = manifest["base"]
    out = {}
    for name, m in manifest["models"].items():
        base = m.get("base", shared_base)
        golden = m["tests"]["golden"]
        perturb = m["tests"]["perturbations"][0]  # gate runs one; full coverage is a tracked follow-up
        out[name] = {
            "image": m["image"].rsplit("/", 1)[-1],  # short name; owner comes from IMAGE_OWNER/gate
            "location": golden["location"],
            "params": golden["params"],
            "perturb": {"param": perturb["param"], "value": perturb["value"]},
            "golden": golden["artifact"],
            "spec_object": m["workspace"]["spec_object"],
            "base_version": str(base["version"]),
        }
    return out


@pytest.fixture(scope="session")
def models_cfg():
    return config()


def image_ref(name: str, image: str) -> str:
    """Candidate digest from the gate, else :latest for local runs."""
    env = f"GATE_IMAGE_{name.replace('-', '_').upper()}"
    if os.environ.get(env):
        return os.environ[env]
    owner = os.environ.get("IMAGE_OWNER", "ncsizemore")
    tag = os.environ.get("GATE_TAG", "latest")
    return f"ghcr.io/{owner}/{image}:{tag}"


def docker_run_json(ref, location, params, run_name, timeout=2700):
    out_dir = pathlib.Path(os.environ.get("GATE_OUT", "/tmp/gate_out"))
    out_dir.mkdir(parents=True, exist_ok=True)
    out_file = out_dir / f"{run_name}.json"
    if out_file.exists():
        out_file.unlink()
    cmd = ["docker", "run", "--rm", "--platform", "linux/amd64",
           "-v", "jheem-gate-cache:/cache", "-v", f"{out_dir}:/out"]
    if os.environ.get("GITHUB_TOKEN"):
        # pass the token through by name (value stays out of the arg list/logs);
        # fetch_simset.R uses it to authenticate api.github.com and avoid the 60/hr limit
        cmd += ["-e", "GITHUB_TOKEN"]
    cmd += [ref, "run", "--location", location]
    for k, v in params.items():
        cmd += ["--param", f"{k}={v}"]
    cmd += ["--out", f"/out/{run_name}.json"]
    proc = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
    if proc.returncode != 0:
        raise AssertionError(
            f"container `run` failed (exit {proc.returncode}) for {run_name}\n"
            f"--- stdout (tail) ---\n{proc.stdout[-2500:]}\n"
            f"--- stderr (tail) ---\n{proc.stderr[-2500:]}")
    return load_json(out_file)


def docker_version(ref):
    r = subprocess.run(["docker", "run", "--rm", "--platform", "linux/amd64", ref, "version"],
                       capture_output=True, text=True, check=True, timeout=300)
    return r.stdout
