"""Static contract tests for the deterministic calibration exporter."""

import json
import pathlib

import jsonschema


REPO = pathlib.Path(__file__).resolve().parents[1]
CALIBRATION = REPO / "calibration" / "ryan-white"
SCHEMA = json.loads((CALIBRATION / "artifact-schema.json").read_text())
EXPORTER = (CALIBRATION / "export_calibration.R").read_text()
SHA = "a" * 64
EXPECTED_UNAVAILABLE = {
    "ryan-white-ajph": set(),
    "ryan-white-croi": {
        ("ehe", "NJ", "ehe-suppression", "no_finite_observations_in_likelihood_window"),
        ("ehe", "PA", "ehe-suppression", "no_finite_observations_in_likelihood_window"),
    },
    "ryan-white-msa": {
        ("ehe", "C.37980", "ehe-awareness", "no_finite_observations_in_likelihood_window"),
        ("ehe", "C.37980", "ehe-suppression", "no_finite_observations_in_likelihood_window"),
        ("ehe", "C.37980", "ehe-testing", "selection_outcome_not_in_archived_manager"),
        ("ehe", "C.47900", "ehe-awareness", "no_finite_observations_in_likelihood_window"),
        ("ehe", "C.47900", "ehe-testing", "selection_outcome_not_in_archived_manager"),
        ("ryan-white", "C.16980", "rw-msa-adap-ratio", "no_finite_observations_in_likelihood_window"),
        ("ryan-white", "C.32820", "rw-msa-adap-ratio", "no_finite_observations_in_likelihood_window"),
        ("ryan-white", "C.35620", "rw-msa-adap-ratio", "no_finite_observations_in_likelihood_window"),
        ("ryan-white", "C.37980", "rw-msa-adap-ratio", "no_finite_observations_in_likelihood_window"),
        ("ryan-white", "C.47900", "rw-msa-adap-ratio", "no_finite_observations_in_likelihood_window"),
    },
}


def test_artifact_schema_has_a_closed_versioned_top_level_contract():
    assert SCHEMA["$schema"] == "https://json-schema.org/draft/2020-12/schema"
    assert SCHEMA["properties"]["schema_version"]["const"] == "jheem-calibration/v1"
    assert SCHEMA["additionalProperties"] is False
    assert set(SCHEMA["required"]) >= {
        "model", "stage", "location", "ensemble", "simulation_source",
        "runtime_source", "exporter_source", "registry_source", "manager_sources", "targets",
        "coverage_source",
    }


def test_artifact_contract_carries_reproducibility_and_uncertainty_fields():
    ensemble = SCHEMA["properties"]["ensemble"]
    assert set(ensemble["required"]) == {
        "sample_count", "kind", "calibration_code", "quantiles"
    }
    posterior = SCHEMA["$defs"]["posteriorPoint"]
    assert set(posterior["required"]) >= {"q025", "q250", "q500", "q750", "q975"}
    assert SCHEMA["$defs"]["fileSource"]["properties"]["sha256"]["pattern"] == (
        "^[0-9a-f]{64}$"
    )
    assert "release" in SCHEMA["$defs"]["simulationSource"]["allOf"][1]["required"]
    runtime_extension = SCHEMA["properties"]["runtime_source"]["allOf"][1]
    assert "image" in runtime_extension["required"]
    assert "@sha256:" in runtime_extension["properties"]["image"]["pattern"]
    manager_extension = SCHEMA["properties"]["manager_sources"]["items"]["allOf"][1]
    assert set(manager_extension["required"]) == {"manager_id", "controlled_release"}


def test_exporter_fails_closed_on_known_provenance_boundaries():
    required_fragments = (
        "simulation asset SHA-256 does not match",
        "simset sample count does not match registry",
        "simset calibration code does not match registry",
        "manager SHA-256 mismatch",
        "--manager IDs must exactly match required managers",
        "derived simulation outcome contains non-finite values",
        "--runtime-image must be an immutable ghcr.io image digest reference",
        "runtime image repository does not match registry model",
        "simulation asset name does not match simset filename",
        "simset location does not match registry geography",
        "has no total-level observations",
        "workspace does not contain required .jheem2_state",
        "workspace .jheem2_state is incomplete",
        "observation coverage registry SHA-256 mismatch",
        "observation coverage target set mismatch",
        "observation coverage contains an unsupported or unresolved status",
    )
    for fragment in required_fragments:
        assert fragment in EXPORTER


def test_exporter_never_uses_serialized_observation_mapping_metadata():
    assert "corresponding.observed.outcome" not in EXPORTER
    assert "manager_bindings" in EXPORTER
    assert "from.ontology.names = binding$ontology" in EXPORTER
    assert "initialize_jheem_runtime(args$workspace)" in EXPORTER
    assert 'get("ONTOLOGY.MAPPING.MANAGER", envir = namespace)' in EXPORTER


def test_exporter_removes_r_group_names_before_json_array_serialization():
    assert "unname(records[order(order_key)])" in EXPORTER


def test_representative_artifact_validates_against_schema():
    artifact = {
        "schema_version": "jheem-calibration/v1",
        "artifact_id": "ryan-white-msa:ryan-white:C.12060",
        "model": "ryan-white-msa",
        "stage": "ryan-white",
        "location": "C.12060",
        "ensemble": {
            "sample_count": 80,
            "kind": "deliberately_thinned_web_delivery",
            "calibration_code": "final.ehe",
            "quantiles": [0.025, 0.25, 0.5, 0.75, 0.975],
        },
        "simulation_source": {
            "release": "ryan-white-msa-v1.0.0",
            "filename": "C.12060_base.Rdata",
            "sha256": SHA,
        },
        "runtime_source": {
            "image": f"ghcr.io/ncsizemore/jheem-ryan-white-msa@sha256:{SHA}",
            "filename": "ryan_white_workspace.RData",
            "sha256": SHA,
        },
        "exporter_source": {"filename": "export_calibration.R", "sha256": SHA},
        "registry_source": {
            "registry_id": "ryan-white-calibration-targets-v1",
            "filename": "registry.yml",
            "sha256": SHA,
        },
        "coverage_source": {
            "filename": "ryan-white-msa.json",
            "sha256": SHA,
        },
        "manager_sources": [{
            "manager_id": "ryan-white-web-display-2025-04-08",
            "controlled_release": "ryan-white-web-display-manager-v2025.04.08",
            "filename": "ryan-white-web-display-manager_2025-04-08.rdata",
            "sha256": SHA,
        }],
        "targets": [{
            "target_id": "rw-non-adap-clients",
            "label": "People receiving non-ADAP Ryan White services",
            "classification": "active_likelihood_target",
            "public_panel": "calibration_target",
            "unit": "people",
            "likelihood_year_window": {"from_year": 2017, "to_year": None},
            "observation_provenance_confidence": "verified",
            "observation_location_binding": "modeled_location",
            "availability": {"status": "available", "reason": None},
            "panels": [{
                "facet": "total",
                "posterior": [{
                    "year": 2020, "stratum": {}, "q025": 1, "q250": 2,
                    "q500": 3, "q750": 4, "q975": 5,
                }],
                "observations": [{
                    "year": 2020, "stratum": {}, "value": 3,
                    "manager_source": "ryan.white.program",
                    "manager_ontology": "ryan.white.pdfs",
                    "public_source_ids": ["hrsa-rwhap-annual"],
                }],
            }],
        }],
    }
    jsonschema.Draft202012Validator(SCHEMA).validate(artifact)


def test_unavailable_target_is_explicit_and_has_no_fit_panel():
    target_schema = {
        "$schema": SCHEMA["$schema"],
        "$defs": SCHEMA["$defs"],
        "$ref": "#/$defs/target",
    }
    validator = jsonschema.Draft202012Validator(target_schema)
    value = {
        "target_id": "ehe-testing",
        "label": "HIV testing",
        "classification": "active_likelihood_target",
        "public_panel": "calibration_target",
        "unit": "proportion",
        "likelihood_year_window": {"from_year": 2008, "to_year": None},
        "observation_provenance_confidence": "reconstructed",
        "observation_location_binding": "nested_likelihood_locations",
        "availability": {
            "status": "unavailable",
            "reason": "selection_outcome_not_in_archived_manager",
        },
        "panels": [],
    }
    validator.validate(value)


def test_reviewed_observation_coverage_has_no_unresolved_errors():
    for model, expected in EXPECTED_UNAVAILABLE.items():
        lock = json.loads(
            (CALIBRATION / "observation-coverage" / f"{model}.json").read_text()
        )
        assert lock["model"] == model
        assert all(record["status"] != "error" for record in lock["records"])
        actual = {
            (record["stage"], record["location"], record["target_id"], record["reason"])
            for record in lock["records"]
            if record["status"] == "unavailable"
        }
        assert actual == expected
