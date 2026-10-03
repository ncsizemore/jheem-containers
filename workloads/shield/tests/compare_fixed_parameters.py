#!/usr/bin/env python3
"""Compare diagnostic values, not serialized simsets or stochastic traces.

The only permitted source difference is an explicitly recorded, test-only
bootstrap substitution selecting the existing hand-sourced engine loader.
Numerical differences are reported, not silently granted a scientific tolerance.
"""

import argparse
import hashlib
import json
import math
from pathlib import Path

BOOTSTRAP = "applications/SHIELD/shield_source_code.R"
PACKAGE_CALL = "pkgload::load_all(JHEEM2.PATH, export_all = TRUE, helpers = FALSE, quiet = TRUE)"
NATIVE_CALL = ('{ SHIELD.COMPARISON.ENGINE.LOADING <- "native-source"; '
               'source(file.path(JHEEM2.PATH, "R/tests/source_jheem2_package.R")) }')


def digest(data):
    return hashlib.sha256(data).hexdigest()


def prepare_native(checkout, plan_path):
    """Use only a disposable copy; refuse drift or a repeated substitution."""
    path = checkout / BOOTSTRAP
    original = path.read_bytes()
    if original.count(PACKAGE_CALL.encode()) != 1 or NATIVE_CALL.encode() in original:
        raise ValueError("Expected exactly one unmodified recorded engine-loading call")
    modified = original.replace(PACKAGE_CALL.encode(), NATIVE_CALL.encode())
    plan = {"path": BOOTSTRAP, "original_sha256": digest(original),
            "native_sha256": digest(modified), "original_call": PACKAGE_CALL,
            "native_call": NATIVE_CALL}
    with plan_path.open("x") as output:
        json.dump(plan, output, indent=2)
    path.write_bytes(modified)


def require(condition, message):
    if not condition:
        raise ValueError(message)


def summarize(left, right):
    require(len(left) == len(right) and len(left) > 0, "Value lengths differ or are empty")
    require(all(type(x) in (float, int) and math.isfinite(x) for x in left + right),
            "Non-finite or nonnumeric values")
    differences = [abs(a - b) for a, b in zip(left, right)]
    relative = [d / max(abs(a), abs(b)) if max(abs(a), abs(b)) else 0.0
                for a, b, d in zip(left, right, differences)]
    index = differences.index(max(differences))
    return {"count": len(left), "different_values": sum(d != 0 for d in differences),
            "max_absolute_difference": max(differences),
            "max_relative_difference": max(relative),
            "worst_absolute_index_1based": index + 1,
            "left_at_worst": left[index], "right_at_worst": right[index]}


def precise(values):
    require(all(isinstance(x, str) for x in values), "Expected full-precision decimal strings")
    return [float(x) for x in values]


def compare(left, right, plan):
    require(left.get("status") == right.get("status") == "passed", "Both checks must pass")
    for key in ("location", "calibration_code", "end_year", "rng_kind", "check_script_sha256"):
        require(key in left and left[key] == right.get(key), f"Different {key}")
    for key in ("analyses_ref", "jheem2_ref", "locations_ref", "bayesian_simulations_ref",
                "distributions_ref", "census_tag", "syphilis_tag", "random_seed"):
        require(left["selection"][key] == right["selection"][key], f"Different selection: {key}")
    for manager in ("census", "syphilis"):
        for key in ("resolved_tag", "sha256"):
            require(left["managers"][manager][key] == right["managers"][manager][key],
                    f"Different manager {manager}: {key}")
    require(isinstance(left.get("parameter_source"), dict), "Missing exact parameter fixture")
    require(left["parameter_source"]["sha256"] == right["parameter_source"]["sha256"],
            "Different parameter fixture bytes")
    a = {x["path"]: x["sha256"] for x in left["source_files"]}
    b = {x["path"]: x["sha256"] for x in right["source_files"]}
    require(a.keys() == b.keys() and BOOTSTRAP in a, "Different source inventory")
    require(plan["path"] == BOOTSTRAP and plan["original_call"] == PACKAGE_CALL and
            plan["native_call"] == NATIVE_CALL, "Unexpected bootstrap adaptation")
    require(a.pop(BOOTSTRAP) == plan["original_sha256"] and
            b.pop(BOOTSTRAP) == plan["native_sha256"], "Bootstrap hash differs from adaptation")
    require(a == b, "Scientific or diagnostic source differs outside the bootstrap adaptation")
    require(right["loading_mode"] == "hand-sourced engine with diagnostic offline bootstrap",
            "Right-hand report did not use the native engine loader")
    require(left["samples"].keys() == right["samples"].keys() and left["samples"],
            "Different or empty parameter cases")
    results = {}
    for name, sample in left["samples"].items():
        other = right["samples"][name]
        require(sample["parameters"] == other["parameters"], f"Different parameters: {name}")
        ac, bc = sample["components"], other["components"]
        require([(x["index"], x["name"]) for x in ac] ==
                [(x["index"], x["name"]) for x in bc], "Likelihood component identities differ")
        likelihood = summarize(precise([x["value_exact"] for x in ac]),
                               precise([x["value_exact"] for x in bc]))
        likelihood["component_names"] = [x["name"] for x in ac]
        require(sample["trajectories"].keys() == other["trajectories"].keys() and
                sample["trajectories"], "Different or empty trajectory coverage")
        outcomes = {}
        for outcome, array in sample["trajectories"].items():
            target = other["trajectories"][outcome]
            require(array["dimensions"] == target["dimensions"], "Trajectory strata/years differ")
            size = math.prod(len(x) for x in array["dimensions"].values())
            require(len(array["values"]) == size, "Malformed trajectory shape")
            row = summarize(precise(array["values"]), precise(target["values"]))
            # R flattens arrays with the first dimension varying fastest.
            offset = row["worst_absolute_index_1based"] - 1
            coordinate = {}
            for dimension, labels in array["dimensions"].items():
                coordinate[dimension] = labels[offset % len(labels)]
                offset //= len(labels)
            row["worst_absolute_coordinate"] = coordinate
            outcomes[outcome] = row
        results[name] = {"likelihood_components": likelihood,
                         "total": summarize(precise([sample["total_exact"]]),
                                            precise([other["total_exact"]])),
                         "trajectories": outcomes}
    groups = [row for result in results.values() for row in
              [result["likelihood_components"], result["total"], *result["trajectories"].values()]]
    return {"schema_version": 1, "status": "compared",
            "agreement": "exact" if all(x["different_values"] == 0 for x in groups) else "different",
            "interpretation": "Descriptive fixed-parameter comparison; no scientific tolerance or MCMC replay claim.",
            "location": left["location"], "calibration_code": left["calibration_code"],
            "left_loading_mode": left["loading_mode"], "right_loading_mode": right["loading_mode"],
            "bootstrap_adaptation": plan, "samples": results}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    prep = commands.add_parser("prepare-native")
    prep.add_argument("checkout", type=Path)
    prep.add_argument("plan", type=Path)
    check = commands.add_parser("compare")
    for name in ("left", "right", "plan", "output"):
        check.add_argument(name, type=Path)
    args = parser.parse_args()
    if args.command == "prepare-native":
        prepare_native(args.checkout, args.plan)
        return
    require(not args.output.exists(), "Refusing to overwrite comparison report")
    result = compare(*(json.loads(path.read_text()) for path in (args.left, args.right, args.plan)))
    with args.output.open("x") as output:
        json.dump(result, output, indent=2, allow_nan=False)
    print(f"Fixed-parameter agreement: {result['agreement']} (see {args.output})")
    for name, sample in result["samples"].items():
        print(f"  {name} / total log likelihood: max |difference| = "
              f"{sample['total']['max_absolute_difference']:.9g}")
        row = sample["likelihood_components"]
        print(f"  {name} / likelihood components: max |difference| = "
              f"{row['max_absolute_difference']:.9g}; {row['different_values']}/{row['count']} differ")
        for outcome, row in sample["trajectories"].items():
            print(f"  {name} / {outcome}: max |difference| = {row['max_absolute_difference']:.9g}; "
                  f"{row['different_values']}/{row['count']} values differ")


if __name__ == "__main__":
    main()
