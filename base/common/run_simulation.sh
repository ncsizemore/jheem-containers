#!/bin/bash
# =============================================================================
# run_simulation.sh
# =============================================================================
# Human-friendly, one-command simulation runner.
#
# Thin facade over custom_simulation.R + batch_plot_generator.R — the SAME
# scripts the web pipeline (run-custom-sim.yml) drives — so a standalone run
# reproduces the pipeline rather than forking a separate sim path.
#
#   docker run --rm --platform linux/amd64 \
#     -v jheem-cache:/cache -v "$PWD/out:/out" \
#     <model-image> run --location C.12580 \
#       --param adap_loss=50 --param oahs_loss=30 --param other_loss=40 \
#       --out /out/results.json
#
# Identity (MODEL_ID, SIMULATION_SCRIPT) and fetch defaults (DEFAULT_OUTCOMES,
# SIMSET_RELEASE) come from the model image's baked ENV; flags override.
# =============================================================================
set -euo pipefail

# --- Image-baked defaults (overridable by flags) ---
MODEL_ID="${MODEL_ID:-}"
SIMULATION_SCRIPT="${SIMULATION_SCRIPT:-}"
OUTCOMES="${DEFAULT_OUTCOMES:-}"
SIMSET_RELEASE="${SIMSET_RELEASE:-}"
SIMSET_REPO="${SIMSET_REPO:-ncsizemore/jheem-simulations}"
SIMSET_BASE_SUFFIX="${SIMSET_BASE_SUFFIX:-_base}"

LOCATION=""
SCENARIO_KEY="custom"
SIMSET=""
OUT="results.json"
STATISTICS="mean.and.interval"
FACETS="sex"
CACHE_DIR="${CACHE_DIR:-/cache}"
declare -a PARAMS=()

usage() {
  cat <<'EOF'
Usage: run [options]

Required:
  --location CODE          Location code (e.g. C.12580 for MSA, AL for state)

Parameters (repeatable; model-specific — see the model's simulation script):
  --param NAME=VALUE       e.g. --param adap_loss=50 --param oahs_loss=30

Base simset source (defaults to fetch-and-cache):
  --simset PATH            Use an explicit base simset file (copied into /data)
  --release TAG            jheem-simulations release to fetch from
                           (default: image's SIMSET_RELEASE)

Output:
  --out PATH               Output JSON path (default: results.json)
  --outcomes LIST          Comma-separated outcomes (default: image DEFAULT_OUTCOMES)
  --scenario-key KEY       Scenario key / label (default: custom)
  --statistics LIST        Default: mean.and.interval
  --facets LIST            Default: sex

Overrides:
  --model ID               Override baked MODEL_ID
  --script NAME            Override baked SIMULATION_SCRIPT
  -h, --help               Show this help

Caching: mount a volume at /cache (e.g. -v jheem-cache:/cache) to fetch each
location's base simset only once per machine.
EOF
}

err() { echo "ERROR: $1" >&2; exit 1; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --location)     LOCATION="${2:-}"; shift 2 ;;
    --param)        PARAMS+=("${2:-}"); shift 2 ;;
    --simset)       SIMSET="${2:-}"; shift 2 ;;
    --release)      SIMSET_RELEASE="${2:-}"; shift 2 ;;
    --out)          OUT="${2:-}"; shift 2 ;;
    --outcomes)     OUTCOMES="${2:-}"; shift 2 ;;
    --scenario-key) SCENARIO_KEY="${2:-}"; shift 2 ;;
    --statistics)   STATISTICS="${2:-}"; shift 2 ;;
    --facets)       FACETS="${2:-}"; shift 2 ;;
    --model)        MODEL_ID="${2:-}"; shift 2 ;;
    --script)       SIMULATION_SCRIPT="${2:-}"; shift 2 ;;
    -h|--help)      usage; exit 0 ;;
    *) echo "ERROR: unknown argument: $1" >&2; echo >&2; usage >&2; exit 1 ;;
  esac
done

# --- Validate ---
[[ -n "$LOCATION" ]]          || err "--location is required"
[[ -n "$MODEL_ID" ]]          || err "MODEL_ID not set (bake ENV MODEL_ID in the model image, or pass --model)"
[[ -n "$SIMULATION_SCRIPT" ]] || err "SIMULATION_SCRIPT not set (bake ENV SIMULATION_SCRIPT, or pass --script)"
[[ -n "$OUTCOMES" ]]          || err "--outcomes is required (no DEFAULT_OUTCOMES baked in image)"

# --- Obtain base simset into /data/ ---
mkdir -p /data
if [[ -n "$SIMSET" ]]; then
  [[ -f "$SIMSET" ]] || err "--simset file not found: $SIMSET"
  echo "Using explicit simset: $SIMSET"
  cp "$SIMSET" /data/
elif ls /data/*.Rdata >/dev/null 2>&1; then
  echo "Using simset(s) already present in /data/"
else
  [[ -n "$SIMSET_RELEASE" ]] || err "no simset: pass --simset PATH, or set --release / SIMSET_RELEASE to fetch"
  # Cache must be writable; fall back to /data (no cross-run persistence) if not.
  if ! mkdir -p "$CACHE_DIR" 2>/dev/null || [[ ! -w "$CACHE_DIR" ]]; then
    echo "NOTE: $CACHE_DIR not writable — fetching without cross-run cache (mount -v ...:/cache to persist)"
    CACHE_DIR="/data"
  fi
  echo "Fetching base simset for $LOCATION from $SIMSET_REPO @ $SIMSET_RELEASE"
  Rscript fetch_simset.R "$SIMSET_RELEASE" "$LOCATION" "$CACHE_DIR/$SIMSET_RELEASE" "/data" \
    "$SIMSET_REPO" "$SIMSET_BASE_SUFFIX"
fi

# --- Export the contract custom_simulation.R + batch_plot_generator.R expect ---
export LOCATION MODEL_ID SIMULATION_SCRIPT SCENARIO_KEY
export SCENARIO_LABEL="$SCENARIO_KEY"
export OUTPUT_DIR=/app           # so simulations/ lands where batch reads it (CWD)
# Map a --param id to its env var via the model's baked PARAM_ENV_MAP (id=ENVVAR
# pairs, the canonical mapping from models.json); fall back to UPPERCASE(id).
# UPPERCASE alone is wrong where id != envVar — e.g. CDC's
# proportion_tested_regardless -> PROPORTION_TESTED (not _REGARDLESS).
resolve_env() {
  local id="$1" pair
  for pair in ${PARAM_ENV_MAP:-}; do
    [ "${pair%%=*}" = "$id" ] && { printf '%s' "${pair#*=}"; return; }
  done
  printf '%s' "$id" | tr '[:lower:]' '[:upper:]'
}
for kv in "${PARAMS[@]}"; do
  [[ "$kv" == *=* && -n "${kv%%=*}" ]] || err "bad --param (expected NAME=VALUE): $kv"
  export "$(resolve_env "${kv%%=*}")"="${kv#*=}"
done

cd /app

echo "=== Step 1/2: simulation ($MODEL_ID / $LOCATION) ==="
Rscript custom_simulation.R

echo "=== Step 2/2: extraction ==="
RUN_OUT="/app/_run_out"
rm -rf "$RUN_OUT"
Rscript batch_plot_generator.R \
  --city "$LOCATION" \
  --scenarios "$SCENARIO_KEY" \
  --outcomes "$OUTCOMES" \
  --statistics "$STATISTICS" \
  --facets "$FACETS" \
  --output-mode data \
  --output-dir "$RUN_OUT"

# --- Hand back a single artifact ---
result="$(find "$RUN_OUT/$LOCATION/$SCENARIO_KEY" -name '*.json' ! -name '*_metadata.json' 2>/dev/null | head -1 || true)"
[[ -n "$result" ]] || err "no output JSON produced — check the extraction logs above"
mkdir -p "$(dirname "$OUT")" 2>/dev/null || true
cp "$result" "$OUT"
echo "Wrote $OUT"
