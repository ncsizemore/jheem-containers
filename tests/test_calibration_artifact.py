"""Static contract tests for the deterministic calibration exporter."""

import json
import pathlib

import jsonschema


REPO = pathlib.Path(__file__).resolve().parents[1]
CALIBRATION = REPO / "calibration" / "ryan-white"
SCHEMA = json.loads((CALIBRATION / "artifact-schema.json").read_text())
EXPORTER = (CALIBRATION / "export_calibration.R").read_text()
SHA = "a" * 64


def test_artifact_schema_has_a_closed_versioned_top_level_contract():
    assert SCHEMA["$schema"] == "https://json-schema.org/draft/2020-12/schema"
    assert SCHEMA["properties"]["schema_version"]["const"] == "jheem-calibration/v1"
    assert SCHEMA["additionalProperties"] is False
    assert set(SCHEMA["required"]) >= {
        "model", "stage", "location", "ensemble", "simulation_source",
        "runtime_source", "exporter_source", "registry_source", "manager_sources", "targets",
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
    )
    for fragment in required_fragments:
        assert fragment in EXPORTER


def test_exporter_never_uses_serialized_observation_mapping_metadata():
    assert "corresponding.observed.outcome" not in EXPORTER
    assert "manager_bindings" in EXPORTER
    assert "from.ontology.names = binding$ontology" in EXPORTER


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
            "observation_provenance_confidence": "verified",
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
