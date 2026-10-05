#!/usr/bin/env bash
# Multi-chain stage check for the recorded SHIELD image.
#
# Runs after test_records_and_pipeline.sh on the same state, where
# container.smoke.stage0 is complete. Proves, for analysis code with recorded
# phases: a pipeline runs a single-chain predecessor, then a four-chain stage as
# one setup, four chain processes, and one assembly; every chain completes; the
# simulation set holds all chains; and every process leaves a succeeded attempt.
# Chains run one at a time here (SHIELD_MAX_PARALLEL_CHAINS=1) to fit a 16 GB
# hosted runner; parallel chains are exercised on a team server.
set -euo pipefail

: "${SHIELD_IMAGE:?SHIELD_IMAGE is required}"
: "${SHIELD_CACHE:?SHIELD_CACHE is required}"
: "${SHIELD_STATE:?SHIELD_STATE is required}"
: "${CENSUS_TAG:?CENSUS_TAG is required}"
: "${SYPHILIS_TAG:?SYPHILIS_TAG is required}"

location="C.12580"
stages=(container.smoke.stage0 container.smoke.pre3 container.smoke.stage3)
run_id="${GITHUB_RUN_ID:-local}-${GITHUB_RUN_ATTEMPT:-1}"
diagnostics="$SHIELD_STATE/diagnostics"
mkdir -p "$diagnostics"

source "$(dirname "${BASH_SOURCE[0]}")/engine-env.sh"

fail() {
  printf 'SHIELD multi-chain test failed: %s\n' "$*" >&2
  exit 1
}

if ! "$engine" run --rm --network none --entrypoint sh "$SHIELD_IMAGE" -c \
    'grep -q "^shield.recorded.phase <- function" "$JHEEM_ANALYSES_PATH/applications/SHIELD/R/shield_recorded_runtime.R"'; then
  echo "SHIELD multi-chain test skipped: this image's analysis code predates recorded phases"
  exit 0
fi

name="shield-multichain-$run_id"
trap '"$engine" rm -f "$name" >/dev/null 2>&1 || true' EXIT
status=0
"$engine" run --name "$name" "${engine_args[@]}" --network none --user "$(id -u):$(id -g)" \
  --mount "type=bind,src=$SHIELD_CACHE,dst=/work/cache,readonly$(mount_opts "$SHIELD_CACHE")" \
  --mount "type=bind,src=$SHIELD_STATE,dst=/work/state$(mount_opts "$SHIELD_STATE")" \
  --env "JHEEM_CENSUS_MANAGER_TAG=$CENSUS_TAG" --env "JHEEM_SYPHILIS_MANAGER_TAG=$SYPHILIS_TAG" \
  --env SHIELD_ENABLE_CONTAINER_SMOKE=true --env SHIELD_CACHE_FREQUENCY=1 --env SHIELD_UPDATE_FREQUENCY=1 \
  --env "SHIELD_RANDOM_SEED=${SHIELD_RANDOM_SEED:-20260916}" --env SHIELD_MAX_PARALLEL_CHAINS=1 \
  --env "SHIELD_IMAGE_ID=$("$engine" image inspect --format '{{.Id}}' "$SHIELD_IMAGE")" \
  "$SHIELD_IMAGE" pipeline "$location" "${stages[@]}" >"$diagnostics/multichain.log" 2>&1 || status=$?
if (( status != 0 )); then
  "$engine" inspect --format 'OOMKilled={{.State.OOMKilled}} ExitCode={{.State.ExitCode}}' "$name" || true
  tail -60 "$diagnostics/multichain.log"
  fail "pipeline exited with status $status"
fi

python3 - "$SHIELD_STATE" "$location" <<'EOF' || fail "multi-chain records are wrong"
import hashlib, json, sys
from pathlib import Path

state, location = sys.argv[1:]
records = Path(state) / "run_records" / "shield" / location / "container.smoke.stage3"

def check(condition, message):
    if not condition:
        sys.exit(f"  {message}")

check((records / "chains.txt").read_text().strip() == "4", "chain count is not 4")
attempts = [json.loads(p.read_text()) for p in sorted((records / "attempts").glob("*.json"))]
shape = sorted((a["phase"], a["chain"] or 0, a["status"]) for a in attempts)
check(shape == [("assemble", 0, "succeeded"), ("run", 1, "succeeded"), ("run", 2, "succeeded"),
                ("run", 3, "succeeded"), ("run", 4, "succeeded"), ("setup", 0, "succeeded")],
      f"stage3 attempts: {shape}")
check(len(list((records / "logs").glob("*-chain*.log"))) == 4, "expected one log per chain")
outputs = json.loads((records / "outputs.json").read_text())
simset = next(o for o in outputs["outputs"] if o["role"] == "simulation_set")
# Four chains of two samples each (no burn-in, no thinning).
check("/container.smoke.stage3-8/" in simset["path"], f"simulation set path: {simset['path']}")
path = Path(state) / simset["path"]
check(hashlib.sha256(path.read_bytes()).hexdigest() == simset["sha256"], "simulation set digest")
preceding = json.loads((records / "inputs.json").read_text())["inputs"]["preceding"]
check([p["calibration_code"] for p in preceding] == ["container.smoke.pre3"], f"preceding: {preceding}")
print("  stage3: 4 chains, 8 simulations, " + f"{simset['bytes'] / 1e6:.1f} MB")
EOF

printf 'SHIELD multi-chain test passed\n'
