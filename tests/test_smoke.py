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
    # The reported base version must match the expected one. Catches a stale /
    # cache-poisoned base: a mutable `FROM …:tag` once let the gha cache serve
    # 1.6.1 layers for a 1.6.3 build, silently shipping models without the base's
    # fetch retries. (FROMs are now digest-pinned; this is defense in depth.)
    expected = models_cfg[name]["base_version"]
    base_line = next((l for l in out.splitlines() if "Base image:" in l), "")
    assert expected in base_line, \
        f"{name}: base version mismatch — expected {expected}, got: '{base_line.strip()}'"

    runtime = models_cfg[name]["runtime"]
    if runtime["simulation_script"] == "simple_ryan_white.R":
        timing = runtime["timing"]
        expected_lines = (
            f"Intervention type:  {runtime['intervention_type']}",
            f"Intervention start: {timing['intervention_start_time']}",
            f"Loss lag (years):   {timing['loss_lag_years']}",
            f"Simulation period:  {timing['simulation_start_year']}-{timing['simulation_end_year']}",
            f"Reporting period:   {timing['reporting_start_year']}-{timing['reporting_end_year']}",
        )
        for expected_line in expected_lines:
            assert expected_line in out, f"{name}: version output missing '{expected_line}'\n{out}"


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
