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

REPO = pathlib.Path(__file__).resolve().parents[1]


def load_json(p):
    with open(p) as f:
        return json.load(f)


def config():
    return load_json(REPO / "tests" / "test_config.json")["models"]


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
           "-v", "jheem-gate-cache:/cache", "-v", f"{out_dir}:/out",
           ref, "run", "--location", location]
    for k, v in params.items():
        cmd += ["--param", f"{k}={v}"]
    cmd += ["--out", f"/out/{run_name}.json"]
    subprocess.run(cmd, check=True, capture_output=True, text=True, timeout=timeout)
    return load_json(out_file)


def docker_version(ref):
    r = subprocess.run(["docker", "run", "--rm", "--platform", "linux/amd64", ref, "version"],
                       capture_output=True, text=True, check=True, timeout=300)
    return r.stdout
