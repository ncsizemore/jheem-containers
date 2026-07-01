"""Validate Dockerfiles + tests/test_config.json agree with models.yml.

models.yml is the canonical container manifest (docs/CONFIG-OWNERSHIP-AND-CONTRACTS.md).
This is the local drift check (migration step 2): every value it owns and that is
mirrored elsewhere must match. Structural + fast (no docker/registry — test_base_pin.py
checks the pinned digest against the registry; transitively models.yml.base.digest ==
Dockerfile digest == registry). Cross-repo validation vs backend models.json is a later step.
"""
import json
import pathlib
import re

import pytest
import yaml

REPO = pathlib.Path(__file__).resolve().parents[1]
MANIFEST = yaml.safe_load((REPO / "models.yml").read_text())
MODELS = list(MANIFEST["models"].keys())


def _dockerfile(name):
    return (REPO / MANIFEST["models"][name]["context"] / "Dockerfile").read_text()


def _arg(text, name):
    m = re.search(rf"ARG {name}=(\S+)", text)
    return m.group(1) if m else None


def _env(text, name):
    m = re.search(rf'(?:^|\s){name}="([^"]*)"', text) or re.search(rf'(?:^|\s){name}=(\S+)', text)
    return m.group(1) if m else None


def _base(name):
    return MANIFEST["models"][name].get("base", MANIFEST["base"])


def test_manifest_covers_all_models():
    cfg = set(json.loads((REPO / "tests" / "test_config.json").read_text())["models"])
    dirs = {p.name for p in (REPO / "models").iterdir() if (p / "Dockerfile").exists()}
    assert set(MODELS) == cfg == dirs, f"models.yml={set(MODELS)} test_config={cfg} model dirs={dirs}"


@pytest.mark.parametrize("name", MODELS)
def test_context_exists(name):
    assert (REPO / MANIFEST["models"][name]["context"] / "Dockerfile").exists()


@pytest.mark.parametrize("name", MODELS)
def test_base_matches_dockerfile(name):
    df, base = _dockerfile(name), _base(name)
    assert _arg(df, "BASE_VERSION") == base["version"], f"{name}: ARG BASE_VERSION != models.yml"
    frm = re.search(r"jheem-base:\$\{BASE_VERSION\}@(sha256:[a-f0-9]{64})", df)
    assert frm and frm.group(1) == base["digest"], f"{name}: FROM digest != models.yml base.digest"


@pytest.mark.parametrize("name", MODELS)
def test_runtime_env_matches(name):
    df, rt = _dockerfile(name), MANIFEST["models"][name]["runtime"]
    assert _env(df, "MODEL_ID") == rt["model_id"], f"{name}: MODEL_ID"
    assert _env(df, "SIMULATION_SCRIPT") == rt["simulation_script"], f"{name}: SIMULATION_SCRIPT"
    assert _env(df, "SIMSET_RELEASE") == rt["simset_release"], f"{name}: SIMSET_RELEASE"
    if "simset_base_suffix" in rt:
        assert _env(df, "SIMSET_BASE_SUFFIX") == rt["simset_base_suffix"], f"{name}: SIMSET_BASE_SUFFIX"


@pytest.mark.parametrize("name", MODELS)
def test_default_cmd_matches(name):
    df, rt = _dockerfile(name), MANIFEST["models"][name]["runtime"]
    m = re.search(r'^CMD \["([^"]+)"\]', df, re.M)
    assert m and m.group(1) == rt["default_cmd"], f"{name}: CMD != models.yml default_cmd"
    assert rt["default_cmd"] in rt["supported_modes"], f"{name}: default_cmd not in supported_modes"


@pytest.mark.parametrize("name", MODELS)
def test_param_env_map_matches(name):
    raw = _env(_dockerfile(name), "PARAM_ENV_MAP") or ""
    baked = dict(kv.split("=") for kv in raw.split()) if raw else {}
    assert baked == MANIFEST["models"][name]["param_env_map"], f"{name}: PARAM_ENV_MAP != models.yml"


@pytest.mark.parametrize("name", MODELS)
def test_jheem_analyses_ref_matches(name):
    src = MANIFEST["models"][name].get("sources", {})
    if "jheem_analyses_ref" not in src:
        pytest.skip("prebuilt model — no jheem_analyses_ref")
    assert _arg(_dockerfile(name), "JHEEM_ANALYSES_COMMIT") == src["jheem_analyses_ref"], \
        f"{name}: JHEEM_ANALYSES_COMMIT != models.yml"


@pytest.mark.parametrize("name", MODELS)
def test_test_config_matches(name):
    cfg = json.loads((REPO / "tests" / "test_config.json").read_text())["models"][name]
    t = MANIFEST["models"][name]["tests"]
    assert cfg["location"] == t["golden"]["location"], f"{name}: golden location"
    assert cfg["params"] == t["golden"]["params"], f"{name}: golden params"
    assert cfg["golden"] == t["golden"]["artifact"], f"{name}: golden artifact"
    assert cfg["spec_object"] == MANIFEST["models"][name]["workspace"]["spec_object"], f"{name}: spec_object"
    perts = [{"param": p["param"], "value": p["value"]} for p in t["perturbations"]]
    assert {"param": cfg["perturb"]["param"], "value": cfg["perturb"]["value"]} in perts, f"{name}: perturbation"
