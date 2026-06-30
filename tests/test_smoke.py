"""Fast smoke tests — image identity + workspace health. No simulation, so cheap
enough to gate every build (the goldens are the slow tier)."""
import subprocess

import pytest

from conftest import config, docker_version, image_ref

MODELS = list(config().keys())


@pytest.mark.parametrize("name", MODELS)
def test_version_provenance(name, models_cfg):
    out = docker_version(image_ref(name, models_cfg[name]["image"]))
    for field in ("Model ID:", "jheem2 (runtime):", "Base image:", "Simset release:"):
        assert field in out, f"{name}: `version` missing '{field}'\n{out}"


@pytest.mark.parametrize("name", MODELS)
def test_workspace_specification(name, models_cfg):
    """`test-workspace` must load the workspace and expose the model's spec object."""
    m = models_cfg[name]
    r = subprocess.run(
        ["docker", "run", "--rm", "--platform", "linux/amd64", image_ref(name, m["image"]),
         "test-workspace"],
        capture_output=True, text=True, timeout=900)
    assert r.returncode == 0, f"{name}: test-workspace failed\n{r.stdout}\n{r.stderr}"
    assert m["spec_object"] in r.stdout, \
        f"{name}: spec object {m['spec_object']} not found in workspace\n{r.stdout}"
