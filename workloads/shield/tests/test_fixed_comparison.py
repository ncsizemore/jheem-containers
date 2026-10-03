import copy
import importlib.util
import json
from pathlib import Path

import pytest
import yaml

spec = importlib.util.spec_from_file_location(
    "fixed_comparison", Path(__file__).with_name("compare_fixed_parameters.py"))
comparison = importlib.util.module_from_spec(spec)
spec.loader.exec_module(comparison)


def fixture():
    record = {
        "status": "passed", "location": "C.12580", "calibration_code": "calib.10.1.stage1",
        "end_year": 2030, "rng_kind": ["Mersenne-Twister", "Inversion", "Rejection"],
        "check_script_sha256": "check", "loading_mode": "installed package",
        "selection": {key: "fixed" for key in
                      ("analyses_ref", "jheem2_ref", "locations_ref", "bayesian_simulations_ref",
                       "distributions_ref", "census_tag", "syphilis_tag", "random_seed")},
        "managers": {name: {"resolved_tag": "tag", "sha256": "manager"}
                     for name in ("census", "syphilis")},
        "parameter_source": {"sha256": "exact-doubles"},
        "source_files": [{"path": comparison.BOOTSTRAP, "sha256": "original"},
                         {"path": "shield_likelihoods.R", "sha256": "science"}],
        "samples": {"prior_medians": {"parameters": {"rate": 1.6}, "total": -3.0, "total_exact": "-3",
                    "components": [{"index": 1, "name": "same-name", "value": -1.0, "value_exact": "-1"},
                                   {"index": 2, "name": "same-name", "value": -2.0, "value_exact": "-2"}],
                    "trajectories": {"population": {
                        "dimensions": {"year": ["2010", "2011"], "sex": ["msm", "female"]},
                        "values": ["10", "20", "30", "40"]}}}}
    }
    native = copy.deepcopy(record)
    native["source_files"][0]["sha256"] = "native"
    native["loading_mode"] = "hand-sourced engine with diagnostic offline bootstrap"
    plan = {"path": comparison.BOOTSTRAP, "original_sha256": "original", "native_sha256": "native",
            "original_call": comparison.PACKAGE_CALL, "native_call": comparison.NATIVE_CALL}
    return record, native, plan


def test_exact_and_different_values_are_distinguished_without_a_tolerance():
    left, right, plan = fixture()
    assert comparison.compare(left, right, plan)["agreement"] == "exact"
    right["samples"]["prior_medians"]["trajectories"]["population"]["values"][2] = "30.1"
    result = comparison.compare(left, right, plan)
    assert result["agreement"] == "different"
    row = result["samples"]["prior_medians"]["trajectories"]["population"]
    assert row["different_values"] == 1
    assert row["max_absolute_difference"] == pytest.approx(0.1)
    assert row["worst_absolute_coordinate"] == {"year": "2010", "sex": "female"}


@pytest.mark.parametrize("change", ["status", "manager", "seed", "source", "fixture",
                                    "parameters", "strata", "nonfinite", "component", "empty"])
def test_incomparable_or_invalid_evidence_fails(change):
    left, right, plan = fixture()
    sample = right["samples"]["prior_medians"]
    if change == "status": right["status"] = "failed"
    if change == "manager": right["managers"]["syphilis"]["sha256"] = "different"
    if change == "seed": right["selection"]["random_seed"] = 1
    if change == "source": right["source_files"][1]["sha256"] = "changed science"
    if change == "fixture": right["parameter_source"]["sha256"] = "rounded"
    if change == "parameters": sample["parameters"]["rate"] = 1.7
    if change == "strata": sample["trajectories"]["population"]["dimensions"]["year"].reverse()
    if change == "nonfinite": sample["trajectories"]["population"]["values"][0] = "nan"
    if change == "component": sample["components"].reverse()
    if change == "empty": right["samples"] = {}
    with pytest.raises(ValueError):
        comparison.compare(left, right, plan)


def test_native_adaptation_is_exact_and_never_repeated(tmp_path):
    bootstrap = tmp_path / comparison.BOOTSTRAP
    bootstrap.parent.mkdir(parents=True)
    bootstrap.write_text("# before\n" + comparison.PACKAGE_CALL + "\n# after\n")
    original = bootstrap.read_bytes()
    plan = tmp_path / "plan.json"
    comparison.prepare_native(tmp_path, plan)
    record = json.loads(plan.read_text())
    assert record["original_sha256"] == comparison.digest(original)
    assert record["native_sha256"] == comparison.digest(bootstrap.read_bytes())
    assert bootstrap.read_text().replace(comparison.NATIVE_CALL, comparison.PACKAGE_CALL).encode() == original
    with pytest.raises(ValueError, match="unmodified"):
        comparison.prepare_native(tmp_path, tmp_path / "second.json")


def test_single_ulp_difference_is_not_rounded_away():
    left, right, plan = fixture()
    left["samples"]["prior_medians"]["components"][0]["value_exact"] = "1.76"
    right["samples"]["prior_medians"]["components"][0]["value_exact"] = "1.7600000000000002"
    result = comparison.compare(left, right, plan)
    assert result["agreement"] == "different"
    assert result["samples"]["prior_medians"]["likelihood_components"]["different_values"] == 1


def test_new_plan_cannot_overwrite_prior_evidence(tmp_path):
    bootstrap = tmp_path / comparison.BOOTSTRAP
    bootstrap.parent.mkdir(parents=True)
    bootstrap.write_text(comparison.PACKAGE_CALL)
    plan = tmp_path / "existing.json"
    plan.write_text("retained")
    with pytest.raises(FileExistsError):
        comparison.prepare_native(tmp_path, plan)
    assert bootstrap.read_text() == comparison.PACKAGE_CALL


def test_workflow_comparison_is_opt_in_and_retains_evidence_on_failure():
    root = Path(__file__).resolve().parents[3]
    workflow = yaml.load((root / ".github/workflows/shield-spike.yml").read_text(), Loader=yaml.BaseLoader)
    assert workflow["on"]["workflow_dispatch"]["inputs"]["compare_fixed_parameters"]["default"] == "false"
    steps = workflow["jobs"]["build-recorded"]["steps"]
    run = next(s for s in steps if s.get("name") == "compare fixed parameters through both engine loaders")
    assert run["if"] == "inputs.compare_fixed_parameters"
    assert "--profile september-2026" in run["run"]
    artifact = next(s for s in steps if s.get("name") == "upload fixed-parameter comparison evidence")
    assert artifact["if"] == "always() && inputs.compare_fixed_parameters"
    script = Path(__file__).with_name("run_fixed_comparison.sh").read_text()
    assert "--network none" in script
    assert "readonly" in script
    assert "org.jheem.shield.jheem2-ref" in script
    assert "SHIELD_SAVE_PARAMETERS" in script and "SHIELD_COMPARISON_PARAMETERS" in script
