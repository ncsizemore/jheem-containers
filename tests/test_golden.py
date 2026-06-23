"""Model-output regression + perturbation tests — the heart of the promotion gate.

- Regression: a fixed scenario must reproduce the committed production golden 0.0.
- Perturbation: a NON-DEFAULT parameter must move the intervention while leaving
  baseline unchanged — proving each parameter reaches the model. This is the test
  that catches the CDC env-var-name class of bug (which a default-valued golden
  silently passed).

These run the full simulation, so they belong on the gate / nightly, not on
every commit. Marked `slow`.
"""
import pytest

from conftest import REPO, config, docker_run_json, image_ref, load_json
from golden_compare import compare_slice, load

MODELS = list(config().keys())


@pytest.mark.slow
@pytest.mark.parametrize("name", MODELS)
def test_golden_regression(name, models_cfg):
    m = models_cfg[name]
    out = docker_run_json(image_ref(name, m["image"]), m["location"], m["params"], f"{name}-golden")
    res = compare_slice(load(REPO / m["golden"]), out)
    assert res.n_common > 0, "no comparable points"
    assert not res.missing and not res.extra, f"missing={res.missing[:3]} extra={res.extra[:3]}"
    assert not res.null_mismatch, f"null-vs-value mismatches: {res.null_mismatch[:3]}"
    assert not res.dup_keys, f"duplicate keys: {res.dup_keys[:3]}"
    assert all(d == 0 for d in res.max_abs_diff_by_role.values()), res.max_abs_diff_by_role


@pytest.mark.slow
@pytest.mark.parametrize("name", MODELS)
def test_param_perturbation(name, models_cfg):
    m = models_cfg[name]
    p = m["perturb"]
    params = dict(m["params"])
    params[p["param"]] = p["value"]
    out = docker_run_json(image_ref(name, m["image"]), m["location"], params, f"{name}-perturb")
    res = compare_slice(load(REPO / m["golden"]), out)  # golden is the default-param run
    assert res.max_abs_diff_by_role.get("baseline", 0) == 0, \
        f"{name}: baseline changed when only an intervention param was perturbed"
    assert res.max_abs_diff_by_role.get("intervention", 0) > 0, \
        f"{name}: perturbing '{p['param']}' did not change the intervention (param not reaching the model)"
