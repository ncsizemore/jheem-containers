"""Fast unit coverage for supported golden artifact shapes."""

from golden_compare import compare_slice


ROW = {
    "year": 2026,
    "value": 1.0,
    "value.lower": 0.5,
    "value.upper": 1.5,
    "simset": "Baseline",
    "facet.by1": "male",
    "stratum": "",
}
SLIM = {"sim": [ROW], "obs": [], "metadata": {}}
PRODUCTION = {
    "data": {
        "scenario": {
            "incidence": {
                "mean.and.interval": {
                    "sex": SLIM,
                },
            },
        },
    },
    "metadata": {},
}


def test_slim_golden_matches_slim_candidate():
    assert compare_slice(SLIM, SLIM).ok


def test_production_golden_matches_slim_candidate():
    assert compare_slice(PRODUCTION, SLIM).ok
