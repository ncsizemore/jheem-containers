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
