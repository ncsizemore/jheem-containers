"""Validate Dockerfiles agree with models.yml.

models.yml is the canonical container manifest (docs/CONFIG-OWNERSHIP-AND-CONTRACTS.md).
This is the local drift check (migration step 2): every value it owns and that is
mirrored in a Dockerfile must match. The test suite itself reads models.yml directly
(conftest.config(); step 3 — the old tests/test_config.json was deleted, not generated),
so there is no test-config mirror left to validate. Structural + fast (no docker/registry
— test_base_pin.py checks the pinned digest against the registry; transitively
models.yml.base.digest == Dockerfile digest == registry; test_cross_repo.py checks the
backend-shared fields). All three run in the CI `contract` job on every PR — a dedicated
job, because the matrix jobs' `-k <model>` would deselect the global (non-parametrized)
checks here.
"""
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
    dirs = {p.name for p in (REPO / "models").iterdir() if (p / "Dockerfile").exists()}
    assert set(MODELS) == dirs, f"models.yml={set(MODELS)} model dirs={dirs}"


@pytest.mark.parametrize("name", MODELS)
def test_golden_artifact_exists(name):
    golden = MANIFEST["models"][name]["tests"]["golden"]
    art = golden["artifact"]
    assert (REPO / art).exists(), f"{name}: golden artifact missing: {art}"
    if "reference_artifact" in golden:
        reference = golden["reference_artifact"]
        assert (REPO / reference).exists(), (
            f"{name}: historical reference artifact missing: {reference}")


@pytest.mark.parametrize("name", MODELS)
def test_perturbation_params_are_known(name):
    m = MANIFEST["models"][name]
    known = set(m["param_env_map"])
    assert set(m["tests"]["golden"]["params"]) <= known, f"{name}: golden params not in param_env_map"
    for p in m["tests"]["perturbations"]:
        assert p["param"] in known, f"{name}: perturbation '{p['param']}' not in param_env_map"


@pytest.mark.parametrize("name", MODELS)
def test_context_exists(name):
    assert (REPO / MANIFEST["models"][name]["context"] / "Dockerfile").exists()


@pytest.mark.parametrize("name", MODELS)
def test_base_matches_dockerfile(name):
    df, base = _dockerfile(name), _base(name)
    assert _arg(df, "BASE_VERSION") == base["version"], f"{name}: ARG BASE_VERSION != models.yml"
    default = _arg(df, "BASE_IMAGE")
    expected = f"{base['image']}:${{BASE_VERSION}}@{base['digest']}"
    assert default == expected, f"{name}: ARG BASE_IMAGE != models.yml base pin"
    assert re.search(r"^FROM \$\{BASE_IMAGE\} AS base$", df, re.M), \
        f"{name}: FROM must consume overridable BASE_IMAGE"


@pytest.mark.parametrize("name", MODELS)
def test_runtime_env_matches(name):
    df, rt = _dockerfile(name), MANIFEST["models"][name]["runtime"]
    assert _env(df, "MODEL_ID") == rt["model_id"], f"{name}: MODEL_ID"
    assert _env(df, "SIMULATION_SCRIPT") == rt["simulation_script"], f"{name}: SIMULATION_SCRIPT"
    assert _env(df, "SIMSET_RELEASE") == rt["simset_release"], f"{name}: SIMSET_RELEASE"
    if "simset_base_suffix" in rt:
        assert _env(df, "SIMSET_BASE_SUFFIX") == rt["simset_base_suffix"], f"{name}: SIMSET_BASE_SUFFIX"
    timing = rt.get("timing")
    if timing:
        expected = {
            "INTERVENTION_TYPE": rt["intervention_type"],
            "INTERVENTION_START_TIME": timing["intervention_start_time"],
            "LOSS_LAG_YEARS": timing["loss_lag_years"],
            "SIMULATION_START_YEAR": timing["simulation_start_year"],
            "SIMULATION_END_YEAR": timing["simulation_end_year"],
            "REPORTING_START_YEAR": timing["reporting_start_year"],
            "REPORTING_END_YEAR": timing["reporting_end_year"],
        }
        for env_name, value in expected.items():
            assert _env(df, env_name) == str(value), f"{name}: {env_name}"


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
