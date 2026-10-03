#!/usr/bin/env python3
"""Compare full-precision SHIELD traces from one identified container setup."""

import argparse
import json
import math
from pathlib import Path


def require(condition, message):
    if not condition:
        raise ValueError(message)


def numeric_groups(value, prefix=""):
    """Preserve axes and order; numerical values use R's 17-digit strings."""
    require(isinstance(value, dict) and value, f"Missing numeric object: {prefix}")
    if set(value) == {"unset"}:
        require(value["unset"] is True, f"Invalid unset marker: {prefix}")
        return {prefix: value}
    if "dimensions" in value or "values" in value:
        axes, values = value.get("dimensions"), value.get("values")
        require(isinstance(axes, dict) and axes, f"Missing axes: {prefix}")
        require(all(isinstance(labels, list) and labels and
                    all(isinstance(x, str) and x for x in labels) and len(set(labels)) == len(labels)
                    for labels in axes.values()), f"Invalid axis labels: {prefix}")
        require(isinstance(values, list) and len(values) == math.prod(map(len, axes.values())),
                f"Value count differs from axes: {prefix}")
        require(all(isinstance(x, str) for x in values), f"Expected precise decimal strings: {prefix}")
        parsed = [float(x) for x in values]
        require(all(math.isfinite(x) for x in parsed), f"Non-finite values: {prefix}")
        return {prefix: {"dimensions": axes, "values": parsed}}
    result = {}
    for name, child in value.items():
        result.update(numeric_groups(child, f"{prefix}/{name}"))
    return result


def validate(report):
    require(report.get("schema_version") == 1 and report.get("status") == "completed",
            "Trace report must describe a completed run")
    setup = report["setup"]
    require(setup["n_chains"] == 1 and setup["n_chunks"] == 4 and
            setup["n_iterations"] == 8 and setup["chunk_sizes"] == [2, 2, 2, 2] and
            setup["thin"] == 1 and setup["burn"] == 0,
            "Expected eight iterations across four two-iteration checkpoints")
    require(setup["variables"] == ["global.transmission.rate.msm", "global.transmission.rate.het"],
            "Unexpected sampled variables")
    require(report["location"] == "C.12580" and
            report["calibration_code"] == "container.smoke.repeatability", "Unexpected test calibration")
    require(report["inputs"]["preceding"] == [], "Replay fixture must not use predecessor output")
    attempts = report["attempts"]
    require(attempts and attempts[-1]["status"] == "succeeded", "No successful final attempt")
    for attempt in attempts:
        require(attempt["image"] == attempts[0]["image"] and
                attempt["image"]["id"].startswith("sha256:") and
                attempt["image"]["profile"] == "recorded", "Attempt image selection drifted")
        require(attempt["settings"] == attempts[0]["settings"], "Attempt settings drifted")
        settings = attempt["settings"]
        require(settings["cache_frequency"] == "2" and settings["update_frequency"] == "1" and
                settings["random_seed"] == report["inputs"]["random_seed"] and
                settings["openblas_num_threads"] == "1", "Unexpected attempt settings")
        for name, field in (("jheem_analyses", "analyses_ref"), ("jheem2", "jheem2_ref"),
                            ("locations", "locations_ref"), ("bayesian_simulations", "bayesian_simulations_ref"),
                            ("distributions", "distributions_ref")):
            require(attempt["sources"][name] == report["inputs"][field], "Attempt source drifted")
    numeric_groups(report["initial"])
    numeric_groups(report["final_state"])
    require(len(report["chunks"]) == 4, "Missing trace chunks")
    for i, chunk in enumerate(report["chunks"], start=1):
        require((chunk["chunk"], chunk["first_iteration"], chunk["last_iteration"]) == (i, 2*i-1, 2*i),
                "Missing, duplicate, or reordered checkpoint coverage")
        require(isinstance(chunk["seed"], str) and chunk["seed"].lstrip("-").isdigit(), "Invalid chunk seed")
        values = numeric_groups(chunk["values"])
        require(set(chunk["values"]) == {"samples", "log.likelihoods", "log.priors",
                                        "n.accepted", "first.step.for.iter"}, "Incomplete numerical trace")
        require(len(values["/samples"]["values"]) == 4 and
                values["/samples"]["dimensions"].get("variable") == setup["variables"] and
                len(values["/log.likelihoods"]["values"]) == 2 and
                len(values["/log.priors"]["values"]) == 2, "Incomplete iteration values")
        numeric_groups(chunk["ending_state"])


def groups(report):
    result = numeric_groups(report["initial"], "initial")
    for chunk in report["chunks"]:
        prefix = f"chunk{chunk['chunk']}"
        result.update(numeric_groups(chunk["values"], f"{prefix}/trace"))
        result.update(numeric_groups(chunk["ending_state"], f"{prefix}/state"))
    result.update(numeric_groups(report["final_state"], "final_state"))
    return result


def compare(left, right, changed_seed=False):
    for report in (left, right):
        validate(report)
    for key in ("location", "calibration_code", "inspector_sha256", "environment", "setup"):
        require(left[key] == right[key], f"Different {key}")
    expected_right = dict(right["inputs"])
    if changed_seed:
        require(left["inputs"]["random_seed"] != right["inputs"]["random_seed"], "Control must change the seed")
        expected_right["random_seed"] = left["inputs"]["random_seed"]
    require(left["inputs"] == expected_right, "Source or manager selections differ")
    require(left["attempts"][0]["image"] == right["attempts"][0]["image"], "Different image")
    a, b = groups(left), groups(right)
    require(a.keys() == b.keys(), "Trace field coverage differs")
    rows = {}
    for name in a:
        if "unset" in a[name] or "unset" in b[name]:
            require(a[name] == b[name], f"Adaptive marker differs: {name}")
            continue
        require(a[name]["dimensions"] == b[name]["dimensions"], f"Axes differ: {name}")
        differences = [abs(x-y) for x, y in zip(a[name]["values"], b[name]["values"])]
        first = next((i for i, d in enumerate(differences) if d != 0), None)
        coordinate = None
        if first is not None:
            coordinate, offset = {}, first
            for axis, labels in a[name]["dimensions"].items():
                coordinate[axis] = labels[offset % len(labels)]
                offset //= len(labels)
        rows[name] = {"count": len(differences), "different_values": sum(x != 0 for x in differences),
                      "max_absolute_difference": max(differences),
                      "first_difference_coordinate": coordinate,
                      "left_at_first_difference": None if first is None else a[name]["values"][first],
                      "right_at_first_difference": None if first is None else b[name]["values"][first]}
    seeds_equal = [x["seed"] for x in left["chunks"]] == [x["seed"] for x in right["chunks"]]
    exact = all(row["different_values"] == 0 for row in rows.values())
    sampled_difference = any(row["different_values"] for name, row in rows.items()
                             if name.endswith("/trace/samples") or name.endswith("/trace/log.likelihoods"))
    passed = (not seeds_equal and sampled_difference) if changed_seed else (seeds_equal and exact)
    return {"passed": passed, "agreement": "exact" if exact else "different",
            "chunk_seeds_equal": seeds_equal, "sample_or_likelihood_difference": sampled_difference,
            "fields": rows}


def experiment(fresh_a, fresh_b, resumed, changed):
    require([(x["run_mode"], x["status"]) for x in resumed["attempts"]] ==
            [("fresh", "started"), ("resume", "started"), ("resume", "succeeded")],
            "Expected interruptions after two separate checkpoints, followed by completion")
    for report in (fresh_a, fresh_b, changed):
        require([(x["run_mode"], x["status"]) for x in report["attempts"]] == [("fresh", "succeeded")],
                "Fresh control must complete in one process")
    comparisons = {"fresh_vs_fresh": compare(fresh_a, fresh_b),
                   "uninterrupted_vs_resumed": compare(fresh_a, resumed),
                   "changed_seed_control": compare(fresh_a, changed, changed_seed=True)}
    return {"schema_version": 1, "status": "passed" if all(x["passed"] for x in comparisons.values()) else "failed",
            "image": fresh_a["attempts"][0]["image"], "inputs": fresh_a["inputs"],
            "environment": fresh_a["environment"], "setup": fresh_a["setup"], "comparisons": comparisons,
            "interpretation": "Eight-iteration, single-chain, same-image experiment; no convergence or general replay claim."}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ("fresh_a", "fresh_b", "resumed", "changed", "output"):
        parser.add_argument(name, type=Path)
    args = parser.parse_args()
    require(not args.output.exists(), "Refusing to overwrite comparison report")
    result = experiment(*(json.loads(getattr(args, name).read_text())
                          for name in ("fresh_a", "fresh_b", "resumed", "changed")))
    with args.output.open("x") as output:
        json.dump(result, output, indent=2, allow_nan=False)
    for name, row in result["comparisons"].items():
        print(f"{name}: {row['agreement']}; check {'passed' if row['passed'] else 'failed'}")
    raise SystemExit(0 if result["status"] == "passed" else 1)


if __name__ == "__main__":
    main()
