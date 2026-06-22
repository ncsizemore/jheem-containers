#!/usr/bin/env python3
"""
Compare a container `run` output against the committed golden reference.

The golden is a *production* custom-sim artifact (full {metadata,data}
aggregation, fetched from CloudFront and blessed by triangulation:
prod == rocker == debian at 0.0 diff). The candidate is the slim output of the
container's `run` mode (one outcome / facet set). We compare the overlapping
slice — by default incidence / mean.and.interval / sex, baseline + intervention.

Exit 0 if every value matches within tolerance, else 1. This guards against
SILENT numerical drift from base-image or dependency changes (the failure a
green build will not catch).
"""
import argparse
import json
import sys


def golden_slice(golden, outcome, statistic, facet):
    data = golden["data"]
    scenario = next(iter(data))  # custom artifact has one scenario key (e.g. a50-o30-r40)
    return data[scenario][outcome][statistic][facet]["sim"]


def index(rows):
    out = {}
    for r in rows:
        role = "base" if r["simset"] == "Baseline" else "intervention"
        out[(role, r["year"], r["facet.by1"], r.get("stratum", ""))] = (
            r.get("value"), r.get("value.lower"), r.get("value.upper"))
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("golden")
    ap.add_argument("candidate")
    ap.add_argument("--outcome", default="incidence")
    ap.add_argument("--statistic", default="mean.and.interval")
    ap.add_argument("--facet", default="sex")
    ap.add_argument("--atol", type=float, default=1e-6)
    a = ap.parse_args()

    G = index(golden_slice(json.load(open(a.golden)), a.outcome, a.statistic, a.facet))
    C = index(json.load(open(a.candidate))["sim"])

    missing = sorted(set(G) - set(C))
    extra = sorted(set(C) - set(G))
    worst, worst_key = 0.0, None
    for k in set(G) & set(C):
        for g, c in zip(G[k], C[k]):
            if g is None or c is None:
                continue
            d = abs(g - c)
            if d > worst:
                worst, worst_key = d, k

    ok = not missing and not extra and worst <= a.atol
    print(f"slice: {a.outcome}/{a.statistic}/{a.facet}")
    print(f"points: golden={len(G)} candidate={len(C)} common={len(set(G) & set(C))}")
    if missing:
        print(f"FAIL: {len(missing)} golden points missing from candidate, e.g. {missing[:3]}")
    if extra:
        print(f"FAIL: {len(extra)} extra candidate points, e.g. {extra[:3]}")
    print(f"max abs diff: {worst} (tol {a.atol})" + (f" @ {worst_key}" if worst_key else ""))
    print("RESULT:", "PASS" if ok else "FAIL")
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
