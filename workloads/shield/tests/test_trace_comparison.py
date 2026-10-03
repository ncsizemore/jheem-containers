import copy
import importlib.util
from pathlib import Path

import pytest

spec = importlib.util.spec_from_file_location(
    "trace_comparison", Path(__file__).with_name("compare_calibration_traces.py"))
comparison = importlib.util.module_from_spec(spec)
spec.loader.exec_module(comparison)


def numeric(values, **axes):
    return {"dimensions": axes or {"element": [str(i+1) for i in range(len(values))]},
            "values": [str(x) for x in values]}


def fixture(seed="0", resumed=False):
    variables = ["global.transmission.rate.msm", "global.transmission.rate.het"]
    refs = {name: "ref" for name in ("analyses_ref", "jheem2_ref", "locations_ref",
                                     "bayesian_simulations_ref", "distributions_ref")}
    inputs = dict(refs, random_seed=seed, census={"tag": "census", "sha256": "census"},
                  syphilis={"tag": "syphilis", "sha256": "syphilis"}, preceding=[])
    attempt = {"run_mode": "fresh", "status": "succeeded",
               "image": {"id": "sha256:test", "profile": "recorded"},
               "sources": {"jheem_analyses": "ref", "jheem2": "ref", "locations": "ref",
                           "bayesian_simulations": "ref", "distributions": "ref"},
               "settings": {"random_seed": seed, "cache_frequency": "2", "update_frequency": "1",
                            "openblas_num_threads": "1"}}
    attempts = [attempt]
    if resumed:
        attempts = [copy.deepcopy(attempt) for _ in range(3)]
        for entry, mode, status in zip(attempts, ("fresh", "resume", "resume"),
                                       ("started", "started", "succeeded")):
            entry.update(run_mode=mode, status=status)
    state = {"current.parameters": numeric([1, 2], element=variables),
             "first.step.for.iter": {"unset": True}, "cov.mat": numeric([1, 0, 0, 1], x=variables, y=variables)}
    chunks = [{"chunk": i, "first_iteration": 2*i-1, "last_iteration": 2*i, "seed": str(i),
               "values": {"samples": numeric([1, 2, 3, 4], chain=["1"], iteration=["1", "2"], variable=variables),
                          "log.likelihoods": numeric([-1, -2], chain=["1"], iteration=["1", "2"]),
                          "log.priors": numeric([-3, -4], chain=["1"], iteration=["1", "2"]),
                          "n.accepted": numeric([1, 1]), "first.step.for.iter": numeric([1, 1])},
               "ending_state": copy.deepcopy(state)} for i in range(1, 5)]
    return {"schema_version": 1, "status": "completed", "location": "C.12580",
            "calibration_code": "container.smoke.repeatability", "inspector_sha256": "script",
            "environment": {"r_version": "4.4.2"}, "inputs": inputs, "attempts": attempts,
            "setup": {"n_chains": 1, "n_chunks": 4, "n_iterations": 8, "chunk_sizes": [2]*4,
                      "thin": 1, "burn": 0, "variables": variables},
            "initial": {"model_parameters": numeric([1, 2])}, "chunks": chunks, "final_state": state}


def test_exact_replay_and_sensitive_control():
    a, b, resumed, changed = fixture(), fixture(), fixture(resumed=True), fixture("1")
    changed["chunks"][0]["seed"] = "123"
    changed["chunks"][0]["values"]["samples"]["values"][0] = "1.1"
    result = comparison.experiment(a, b, resumed, changed)
    assert result["status"] == "passed"
    assert result["comparisons"]["fresh_vs_fresh"]["agreement"] == "exact"
    assert result["comparisons"]["uninterrupted_vs_resumed"]["agreement"] == "exact"
    assert result["comparisons"]["changed_seed_control"]["sample_or_likelihood_difference"]


def test_one_ulp_difference_is_reported_at_the_checkpoint():
    left, right = fixture(), fixture(resumed=True)
    right["chunks"][1]["values"]["samples"]["values"][0] = "1.0000000000000002"
    result = comparison.compare(left, right)
    assert not result["passed"]
    row = result["fields"]["chunk2/trace/samples"]
    assert row["different_values"] == 1
    assert row["first_difference_coordinate"] == {
        "chain": "1", "iteration": "1", "variable": "global.transmission.rate.msm"}


@pytest.mark.parametrize("bad", ["manager", "image", "checkpoint", "coverage", "seed", "nan", "initial", "state"])
def test_invalid_or_divergent_comparisons_cannot_pass(bad):
    left, right = fixture(), fixture(resumed=True)
    if bad == "manager": right["inputs"]["syphilis"]["sha256"] = "different"
    if bad == "image": right["attempts"][1]["image"]["id"] = "sha256:different"
    if bad == "checkpoint": right["chunks"][1]["first_iteration"] = 1
    if bad == "coverage": right["chunks"][0]["values"]["samples"]["values"].pop()
    if bad == "seed": right["chunks"][0]["seed"] = "123"
    if bad == "nan": right["chunks"][0]["values"]["log.likelihoods"]["values"][0] = "nan"
    if bad == "initial": right["initial"]["model_parameters"]["values"][0] = "2"
    if bad == "state": right["final_state"]["cov.mat"]["values"][0] = "2"
    if bad in ("seed", "initial", "state"):
        assert not comparison.compare(left, right)["passed"]
    else:
        with pytest.raises(ValueError):
            comparison.compare(left, right)


def test_changed_label_or_changed_checkpoint_seed_alone_is_not_a_sensitive_control():
    left, right = fixture(), fixture("1")
    assert not comparison.compare(left, right, changed_seed=True)["passed"]
    right["chunks"][0]["seed"] = "123"
    assert not comparison.compare(left, right, changed_seed=True)["passed"]


def test_completion_after_only_one_interruption_does_not_satisfy_this_experiment():
    with pytest.raises(ValueError, match="two separate checkpoints"):
        comparison.experiment(fixture(), fixture(), fixture(resumed=True) | {"attempts": fixture()["attempts"]}, fixture("1"))
