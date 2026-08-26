"""Contract tests for the release-specific Ryan White calibration registry."""

import pathlib
import re

import yaml


REPO = pathlib.Path(__file__).resolve().parents[1]
REGISTRY_PATH = REPO / "calibration/ryan-white/registry.yml"
REGISTRY = yaml.safe_load(REGISTRY_PATH.read_text())
MODELS = yaml.safe_load((REPO / "models.yml").read_text())["models"]
HEX_64 = re.compile(r"^[0-9a-f]{64}$")


def test_registry_identity_and_scope_are_explicit():
    assert REGISTRY["schema_version"] == "jheem-calibration-target-registry/v1"
    assert REGISTRY["scope"] == "initial_public_panel_allowlist"
    assert REGISTRY["coverage_status"] == "partial"
    assert REGISTRY["policies"]["observation_binding"] == "explicit_registry_only"
    assert REGISTRY["policies"]["simset_metadata_binding"] == "prohibited"
    assert REGISTRY["policies"]["legacy_adap_mapping"] == (
        "reject_adap_clients_to_non_adap_clients"
    )
    assert REGISTRY["policies"]["manager_binding_semantics"] == (
        "all_explicit_series_mappable_to_model_geography"
    )


def test_registry_covers_exactly_the_deployed_ryan_white_models():
    expected = {name for name in MODELS if name.startswith("ryan-white-")}
    assert set(REGISTRY["models"]) == expected
    for model_id, model in REGISTRY["models"].items():
        assert model["backend_model_id"] == MODELS[model_id]["backend_model_id"]
        assert model["runtime_image_repository"] == MODELS[model_id]["image"]


def test_service_fit_releases_match_container_runtime_manifest():
    for model_id, entry in REGISTRY["models"].items():
        assert entry["stages"]["ryan-white"]["simulation_release"] == (
            MODELS[model_id]["runtime"]["simset_release"]
        )


def test_every_stage_is_release_specific_and_resolvable():
    for model_id, model in REGISTRY["models"].items():
        assert set(model["stages"]) == {"ehe", "ryan-white"}
        for stage_id, stage in model["stages"].items():
            assert stage["sample_count"] > 0, (model_id, stage_id)
            assert stage["simulation_release"]
            assert stage["asset_digest_policy"] == "per_location_release_asset"
            assert stage["target_set"] in REGISTRY["target_sets"]
            assert stage["definition_evidence"] in REGISTRY["definition_evidence"]
            assert REGISTRY["target_sets"][stage["target_set"]]["stage"] == stage_id


def test_definition_and_compatibility_evidence_use_full_revisions():
    for evidence_id, evidence in REGISTRY["definition_evidence"].items():
        assert re.fullmatch(r"[0-9a-f]{40}", evidence["revision"]), evidence_id
    for evidence_id, evidence in REGISTRY["compatibility_evidence"].items():
        assert re.fullmatch(r"[0-9a-f]{40}", evidence["revision"]), evidence_id
        assert evidence["scope"] == "selective_target_compatibility"


def test_deployed_ensemble_sizes_are_not_conflated():
    models = REGISTRY["models"]
    assert models["ryan-white-msa"]["stages"]["ehe"]["sample_count"] == 1000
    assert models["ryan-white-msa"]["stages"]["ryan-white"]["sample_count"] == 80
    for model_id in ("ryan-white-ajph", "ryan-white-croi"):
        assert models[model_id]["stages"]["ehe"]["sample_count"] == 1000
        assert models[model_id]["stages"]["ryan-white"]["sample_count"] == 1000


def test_manager_records_are_hash_pinned_and_controlled():
    for manager_id, manager in REGISTRY["data_managers"].items():
        assert HEX_64.fullmatch(manager["sha256"]), manager_id
        assert manager["controlled_release"].startswith("ryan-white-"), manager_id
        assert manager["asset_filename"].endswith(".rdata"), manager_id
        assert manager["redistribution"] == "controlled_only"
        assert manager["historical_fitting_identity"] in {"verified", "reconstructed", "unknown"}


def test_sources_have_https_urls_attribution_and_reuse_disposition():
    for source_id, source in REGISTRY["sources"].items():
        assert source["url"].startswith("https://"), source_id
        assert source["attribution_required"] is True, source_id
        assert source["public_reuse_status"], source_id


def test_lhd_observations_are_explicitly_excluded_from_public_v1():
    exclusion = REGISTRY["policies"]["public_observation_exclusions"]
    assert exclusion == [{
        "policy_id": "lhd-suppression-public-v1",
        "source_id": "local-health-department-suppression",
        "manager_source": "lhd",
        "manager_ontology": "lhd",
        "reason": "unresolved_source_identity_and_reuse_terms",
        "scope": "public_calibration_artifacts",
    }]
    assert REGISTRY["sources"]["local-health-department-suppression"][
        "public_reuse_status"
    ] == "excluded_from_public_v1_pending_provenance_and_reuse_confirmation"
    bindings = REGISTRY["targets"]["ehe-suppression"]["observation"][
        "manager_bindings"
    ]["msa"]
    assert all(binding["source"] != "lhd" for binding in bindings)
    assert all(binding["ontology"] != "lhd" for binding in bindings)
    assert all(
        "local-health-department-suppression" not in binding["public_source_ids"]
        for binding in bindings
    )


def test_target_sets_reference_unique_known_targets_for_the_correct_stage():
    targets = REGISTRY["targets"]
    for set_id, target_set in REGISTRY["target_sets"].items():
        ids = target_set["target_ids"]
        assert len(ids) == len(set(ids)), set_id
        for target_id in ids:
            assert target_id in targets, (set_id, target_id)
            assert targets[target_id]["stage"] == target_set["stage"]


def test_observation_bindings_are_explicit_and_resolvable():
    managers = REGISTRY["data_managers"]
    sources = REGISTRY["sources"]
    for target_id, target in REGISTRY["targets"].items():
        observation = target["observation"]
        assert observation["binding"].startswith("explicit"), target_id
        assert observation["manager"] in managers, target_id
        assert observation["source_ids"], target_id
        assert set(observation["source_ids"]) <= set(sources), target_id
        assert observation["provenance_confidence"] in {
            "verified", "reconstructed", "unknown"
        }


def test_exported_targets_have_explicit_manager_source_and_ontology_bindings():
    sources = REGISTRY["sources"]
    for model_id, model in REGISTRY["models"].items():
        geography = model["geography"]
        for stage in model["stages"].values():
            target_ids = REGISTRY["target_sets"][stage["target_set"]]["target_ids"]
            for target_id in target_ids:
                target = REGISTRY["targets"][target_id]
                bindings = target["observation"]["manager_bindings"].get(geography)
                assert bindings, (model_id, stage["target_set"], target_id)
                for binding in bindings:
                    assert binding["source"], target_id
                    assert binding["ontology"], target_id
                    assert binding["public_source_ids"], target_id
                    assert set(binding["public_source_ids"]) <= set(sources), target_id


def test_derived_simulation_targets_use_structured_allowlisted_operations():
    for target_id, target in REGISTRY["targets"].items():
        simulation = target["simulation"]
        if "expression" not in simulation:
            continue
        derivation = simulation["derivation"]
        assert derivation["operation"] == "multiply_divide", target_id
        assert derivation["numerator_outcomes"], target_id
        assert derivation["denominator_outcomes"], target_id
        assert simulation["ontology_outcome"], target_id


def test_nested_msa_targets_encode_the_historical_location_selection_rule():
    for target_id in (
        "rw-msa-adap-ratio",
        "rw-msa-adap-suppressed-share-diagnosed",
    ):
        target = REGISTRY["targets"][target_id]
        assert target["observation"]["location_binding"] == (
            "nested_likelihood_locations"
        )
        likelihood = target["likelihood"]
        assert likelihood["kind"] == "nested_proportion"
        assert likelihood["location_types"] == ["STATE", "CBSA"]
        assert likelihood["maximum_locations_per_type"] == 2
        assert likelihood["minimum_geographic_resolution_type"] == "COUNTY"


def test_ehe_location_bindings_match_likelihood_geography_rules():
    awareness = REGISTRY["targets"]["ehe-awareness"]
    assert awareness["facets"] == ["total"]

    direct_msa_locations = {
        "C.29820", "C.31080", "C.33100", "C.40140", "C.41740",
    }
    for target_id in ("ehe-awareness", "ehe-suppression"):
        target = REGISTRY["targets"][target_id]
        binding = target["observation"]["location_binding"]
        assert binding["state"] == "modeled_location"
        assert binding["msa"]["default"] == "nested_likelihood_locations"
        assert set(binding["msa"]["modeled_locations"]) == direct_msa_locations
        assert target["likelihood"]["maximum_locations_per_type"] == 3
        assert target["likelihood"]["minimum_geographic_resolution_type"] == "COUNTY"

    testing = REGISTRY["targets"]["ehe-testing"]
    assert testing["observation"]["location_binding"] == {
        "state": "modeled_location",
        "msa": "nested_likelihood_locations",
    }
    assert testing["likelihood"]["location_types"] == ["STATE", "CBSA"]
    assert testing["likelihood"]["maximum_locations_per_type"] == 3


def test_legacy_adap_client_mapping_cannot_reenter_the_export_contract():
    target = REGISTRY["targets"]["rw-state-adap-clients"]
    assert target["simulation"]["outcome"] == "adap.clients"
    assert target["observation"]["outcome"] == "adap.clients"
    assert target["observation"]["reject_simset_mapping"] == "non.adap.clients"
    for target_id, entry in REGISTRY["targets"].items():
        if entry["simulation"]["outcome"] == "adap.clients":
            assert entry["observation"]["outcome"] != "non.adap.clients", target_id


def test_active_targets_record_likelihood_and_public_interpretation():
    allowed_panels = {
        "calibration_target", "calibration_target_with_reconstructed_observations",
        "model_fit_check", "related_model_fit_check", "not_exported",
    }
    for target_id, target in REGISTRY["targets"].items():
        assert target["classification"] in {
            "active_likelihood_target", "active_likelihood_family"
        }, target_id
        assert target["likelihood"]["kind"], target_id
        assert target["public_panel"] in allowed_panels, target_id


def test_exhaustive_service_sets_include_all_six_likelihood_families():
    msa = REGISTRY["target_sets"]["ryan-white-msa-v1"]
    state = REGISTRY["target_sets"]["ryan-white-state-v1"]
    assert msa["exhaustive"] is True and len(msa["target_ids"]) == 6
    assert state["exhaustive"] is True and len(state["target_ids"]) == 6
    assert "rw-non-adap-sex-risk-distribution" in msa["target_ids"]
    assert "rw-non-adap-sex-risk-distribution" in state["target_ids"]


def test_registry_contains_no_local_filesystem_paths():
    raw = REGISTRY_PATH.read_text()
    assert "/Users/" not in raw
    assert "/Volumes/" not in raw
    assert "Q:/" not in raw
