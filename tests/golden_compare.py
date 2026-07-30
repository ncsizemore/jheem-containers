"""
Robust comparison of a container `run` output against a production golden.

Addresses the golden-coverage gaps the independent review flagged:
- compares any number of (outcome, statistic, facet) slices, not just one;
- treats null-vs-value as a MISMATCH, not a silent skip;
- detects duplicate index keys (would otherwise overwrite rows silently);
- reports per-role (baseline vs intervention) so a perturbation test can assert
  "baseline unchanged, intervention moved".

Golden format may be either the production custom-sim artifact ({metadata,
data: {scenario: {outcome: {statistic: {facet: {sim: [...], obs,
metadata}}}}}}) or a reviewed slim `run` output ({sim, obs, metadata}).
Candidate format (the slim `run` output): {sim: [...], obs, metadata} for the
single outcome/facets that `run` produced.
"""
from __future__ import annotations
import json
from dataclasses import dataclass, field


def _role(simset: str) -> str:
    return "baseline" if simset == "Baseline" else "intervention"


def _index(rows, outcome, statistic, facet):
    """Index sim rows by (role, year, facet_value, stratum) -> (value, lower, upper).
    Raises on duplicate keys."""
    out, dups = {}, []
    for r in rows:
        key = (_role(r["simset"]), r["year"], r.get("facet.by1"), r.get("stratum", ""))
        if key in out:
            dups.append(key)
        out[key] = (r.get("value"), r.get("value.lower"), r.get("value.upper"))
    return out, dups


def _golden_rows(golden, outcome, statistic, facet):
    if "sim" in golden:
        return golden["sim"]
    data = golden["data"]
    scenario = next(iter(data))  # custom artifact has a single scenario key
    return data[scenario][outcome][statistic][facet]["sim"]


@dataclass
class SliceResult:
    outcome: str
    facet: str
    statistic: str
    n_common: int = 0
    missing: list = field(default_factory=list)   # in golden, absent from candidate
    extra: list = field(default_factory=list)     # in candidate, absent from golden
    null_mismatch: list = field(default_factory=list)
    dup_keys: list = field(default_factory=list)
    max_abs_diff_by_role: dict = field(default_factory=dict)

    @property
    def ok(self) -> bool:
        return (not self.missing and not self.extra and not self.null_mismatch
                and not self.dup_keys
                and all(d == 0 for d in self.max_abs_diff_by_role.values()))


def compare_slice(golden, candidate, outcome="incidence",
                  statistic="mean.and.interval", facet="sex", atol=1e-6) -> SliceResult:
    res = SliceResult(outcome=outcome, facet=facet, statistic=statistic)
    G, gdup = _index(_golden_rows(golden, outcome, statistic, facet), outcome, statistic, facet)
    C, cdup = _index(candidate["sim"], outcome, statistic, facet)
    res.dup_keys = gdup + cdup
    res.missing = sorted(set(G) - set(C))
    res.extra = sorted(set(C) - set(G))
    by_role: dict = {}
    for k in set(G) & set(C):
        role = k[0]
        for g, c in zip(G[k], C[k]):
            if (g is None) != (c is None):          # null vs present = mismatch
                res.null_mismatch.append(k)
                continue
            if g is None and c is None:
                continue
            d = abs(g - c)
            by_role[role] = max(by_role.get(role, 0.0), d if d > atol else 0.0)
    res.n_common = len(set(G) & set(C))
    res.max_abs_diff_by_role = by_role
    return res


def load(path):
    with open(path) as f:
        return json.load(f)
