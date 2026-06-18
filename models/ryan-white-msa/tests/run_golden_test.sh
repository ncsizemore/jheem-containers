#!/bin/bash
# =============================================================================
# Golden-output regression test (Ryan White MSA)
# =============================================================================
# Runs a fixed custom scenario through the container and diffs the result
# against a committed golden — a production custom-sim artifact blessed by
# triangulation (prod == rocker == debian, 0.0 diff). Catches SILENT numerical
# drift from base-image / dependency changes that a green build would not.
#
# Usage: tests/run_golden_test.sh <model-image> [cache-volume]
#   e.g. tests/run_golden_test.sh ghcr.io/ncsizemore/jheem-ryan-white-msa:latest
#
# Note: this is an integration test — it downloads the base simset (cached in
# the named volume after the first run) and runs the full ~5 min simulation.
# =============================================================================
set -euo pipefail

IMAGE="${1:?usage: run_golden_test.sh <model-image> [cache-volume]}"
CACHE="${2:-jheem-golden-cache}"
DIR="$(cd "$(dirname "$0")" && pwd)"
OUT="$(mktemp -d)"
trap 'rm -rf "$OUT"' EXIT

docker run --rm --platform linux/amd64 \
  -v "${CACHE}:/cache" -v "${OUT}:/out" \
  "$IMAGE" \
  run --location C.12580 \
      --param adap_loss=50 --param oahs_loss=30 --param other_loss=40 \
      --outcomes incidence --facets sex \
      --out /out/results.json

python3 "$DIR/compare_golden.py" \
  "$DIR/golden/C.12580_a50-o30-r40.json" "$OUT/results.json"
