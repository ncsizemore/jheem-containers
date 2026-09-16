"""Structural checks for fail-closed model testing and promotion."""

from pathlib import Path

import yaml


REPO = Path(__file__).resolve().parents[1]
WORKFLOW = yaml.load(
    (REPO / ".github/workflows/build.yml").read_text(),
    Loader=yaml.BaseLoader,
)


def _condition(job):
    return " ".join(WORKFLOW["jobs"][job]["if"].split())


def _select_script():
    step = next(
        step for step in WORKFLOW["jobs"]["select"]["steps"]
        if step.get("id") == "pick"
    )
    return step["run"]


def test_model_tests_tolerate_only_the_expected_skipped_base_ancestor():
    condition = _condition("test-models")

    assert "always()" in condition
    assert "needs.select.result == 'success'" in condition
    assert "needs.build-models.result == 'success'" in condition
    assert "needs.select.outputs.models_any == 'true'" in condition


def test_model_promotion_cannot_inherit_a_skipped_base_ancestor():
    condition = _condition("promote-models")

    assert "always()" in condition
    assert "needs.select.result == 'success'" in condition
    assert "needs.build-models.result == 'success'" in condition
    assert "needs.test-models.result == 'success'" in condition
    assert "needs.contract.result == 'success'" in condition
    assert "needs.select.outputs.promotions_any == 'true'" in condition


def test_model_promotion_uses_the_narrow_promotion_matrix():
    select_outputs = WORKFLOW["jobs"]["select"]["outputs"]
    promote_matrix = WORKFLOW["jobs"]["promote-models"]["strategy"]["matrix"]

    assert "promotion_matrix" in select_outputs
    assert "promotions_any" in select_outputs
    assert promote_matrix["include"] == (
        "${{ fromJSON(needs.select.outputs.promotion_matrix) }}"
    )
    assert "model_matrix" not in promote_matrix["include"]


def test_main_promotion_eligibility_comes_only_from_model_contexts():
    script = _select_script()

    assert 'promote_names=""' in script
    assert '[ "$GITHUB_REF" = "refs/heads/main" ]' in script
    assert 'grep -q "^models/$name/"' in script
    assert 'promote_names="$promote_names $name"' in script
    assert 'promotion_matrix=$(echo "$MODELS"' in script


def test_shared_validation_paths_do_not_directly_grant_promotion():
    script = _select_script()

    assert "'^(tests/|\\.github/|models\\.yml$)'" in script
    assert 'pick="MODELS"' in script
    assert 'promote_names="MODELS"' not in script
    assert 'promotion_matrix="$MODELS"' not in script


def test_selector_fails_closed_for_unknown_manual_and_tag_targets():
    script = _select_script()

    assert "unknown workflow_dispatch image" in script
    assert "tag target is not in models.yml" in script
    assert script.count("exit 1") >= 2


def test_workflow_changes_exercise_the_base_cascade():
    script = _select_script()

    assert "^\\.github/workflows/build\\.yml$" in script
