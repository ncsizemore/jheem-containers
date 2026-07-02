"""Cross-repo contract: models.yml vs backend models.json (migration steps 4+5).

Backend jheem-backend/.github/config/models.json owns the app/product contract —
including the custom-sim parameter id -> envVar mapping (the CDC bug was this
drifting). models.yml owns the container contract. Shared fields must AGREE; this
module enforces that on every PR (docs/CONFIG-OWNERSHIP-AND-CONTRACTS.md).

Fetches the backend manifest from raw.githubusercontent (the repo is public; no
credentials). Overrides:
  BACKEND_REF          git ref to check against (default: master) — for
                       coordinated cross-repo changes;
  BACKEND_MODELS_PATH  local file path (e.g. a backend clone) — offline work.
A failed fetch FAILS the suite (never skips): a silently-skipped contract check
is a misleading green.
"""
import json
import os
import pathlib
import time
import urllib.request

import pytest
import yaml

REPO = pathlib.Path(__file__).resolve().parents[1]
MANIFEST = yaml.safe_load((REPO / "models.yml").read_text())
MODELS = list(MANIFEST["models"].keys())

BACKEND_REPO = "ncsizemore/jheem-backend"
BACKEND_PATH = ".github/config/models.json"


def _fetch_backend():
    local = os.environ.get("BACKEND_MODELS_PATH")
    if local:
        return json.loads(pathlib.Path(local).read_text())
    ref = os.environ.get("BACKEND_REF", "master")
    url = f"https://raw.githubusercontent.com/{BACKEND_REPO}/{ref}/{BACKEND_PATH}"
    last = None
    for attempt in range(4):
        try:
            with urllib.request.urlopen(url, timeout=30) as r:
                return json.loads(r.read().decode())
        except Exception as e:  # noqa: BLE001 — retry any transient fetch error
            last = e
            time.sleep(2 * (attempt + 1))
    raise AssertionError(f"could not fetch backend manifest {url}: {last}")


@pytest.fixture(scope="session")
def backend():
    return _fetch_backend()


def _backend_model(backend, name):
    bid = MANIFEST["models"][name]["backend_model_id"]
    assert bid in backend, f"{name}: backend_model_id '{bid}' not in backend models.json"
    return backend[bid]


@pytest.mark.parametrize("name", MODELS)
def test_backend_model_exists(name, backend):
    _backend_model(backend, name)


@pytest.mark.parametrize("name", MODELS)
def test_param_env_map_agrees_with_backend(name, backend):
    """Step 4: backend owns id->envVar; the container map must match it exactly."""
    theirs = {p["id"]: p["envVar"]
              for p in _backend_model(backend, name)["customSimulation"]["parameters"]}
    ours = MANIFEST["models"][name]["param_env_map"]
    assert ours == theirs, (
        f"{name}: param_env_map disagrees with backend models.json "
        f"(owner: backend customSimulation.parameters)\n"
        f"  container: {ours}\n  backend:   {theirs}")


@pytest.mark.parametrize("name", MODELS)
def test_simulation_script_agrees(name, backend):
    theirs = _backend_model(backend, name)["customSimulation"]["simulationScript"]
    ours = MANIFEST["models"][name]["runtime"]["simulation_script"]
    assert ours == theirs, f"{name}: simulation_script container={ours} backend={theirs}"


@pytest.mark.parametrize("name", MODELS)
def test_image_name_agrees(name, backend):
    theirs = _backend_model(backend, name)["container"]["image"]
    ours = MANIFEST["models"][name]["image"]
    assert ours == theirs, f"{name}: image container={ours} backend={theirs}"


@pytest.mark.parametrize("name", MODELS)
def test_simset_release_agrees(name, backend):
    theirs = _backend_model(backend, name)["dataSource"]["release"]
    ours = MANIFEST["models"][name]["runtime"]["simset_release"]
    assert ours == theirs, f"{name}: simset release container={ours} backend={theirs}"


def test_all_backend_custom_sim_models_are_containerized(backend):
    """Reverse direction: every backend model with a customSimulation block must
    have a container entry here — a backend model nobody builds is a gap."""
    backend_ids = {k for k, v in backend.items()
                   if isinstance(v, dict) and "customSimulation" in v}
    ours = {m["backend_model_id"] for m in MANIFEST["models"].values()}
    assert backend_ids <= ours, f"backend models without a container: {backend_ids - ours}"
