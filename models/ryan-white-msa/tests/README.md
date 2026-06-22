# Golden-output regression test

Guards against **silent numerical drift** — when a base-image or dependency
change still builds green but quietly changes the model's output. A regular
build failure (e.g. the V8/Node-24 break) is caught by the build itself; a
silent value change is *only* caught by comparing output to a known-good
reference.

## The golden

`golden/C.12580_a50-o30-r40.json` is a **production** custom-sim artifact —
fetched from CloudFront (`/ryan-white/custom/C.12580/a50-o30-r40.json`,
generated 2026-03-19 by the live pipeline). It was chosen as the golden, rather
than a local run, for provenance: it's the artifact actually served to users.

Its correctness was established by **triangulation** — the production result,
a rocker-base build, and a Debian-base build all agree bit-for-bit (max abs
diff `0.0`) on baseline + intervention, so the golden is well-founded and not a
regressed snapshot.

## Running it

```bash
tests/run_golden_test.sh ghcr.io/ncsizemore/jheem-ryan-white-msa:latest
```

Runs `adap_loss=50 / oahs_loss=30 / other_loss=40` for `C.12580`, then diffs
the output against the golden (exit non-zero on any diff beyond `--atol`). It's
an integration test: it downloads the base simset (cached in the named volume
after the first run) and runs the full ~5 min simulation, so it belongs on
container builds / nightly, not every commit.

## Scope (and roadmap)

Currently compares the **incidence / mean.and.interval / sex** slice (baseline +
intervention) — the headline epidemiological outcome, a good canary for engine
drift. The golden file contains the *full* aggregation, so widening the test to
more outcomes/facets is just a flag change in `run_golden_test.sh` +
`compare_golden.py`. Per-model goldens for AJPH / CROI / CDC-Testing (34 cached
production results exist across the four models) are the natural next step.
