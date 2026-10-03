#!/usr/bin/env bash
# Same-image fresh/fresh and uninterrupted/resumed traces, plus a changed seed.
# State is new and local to this experiment; completed chunks are preserved.
set -euo pipefail
: "${SHIELD_IMAGE:?SHIELD_IMAGE is required}"
: "${SHIELD_CACHE:?SHIELD_CACHE is required}"
: "${SHIELD_REPLAY_OUTPUT:?SHIELD_REPLAY_OUTPUT is required}"
: "${CENSUS_TAG:?CENSUS_TAG is required}"
: "${SYPHILIS_TAG:?SYPHILIS_TAG is required}"

scripts="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$scripts/engine-env.sh"
[[ ! -e "$SHIELD_REPLAY_OUTPUT" ]] || { echo 'Replay output already exists' >&2; exit 1; }
mkdir -p "$SHIELD_REPLAY_OUTPUT"
image_id="$("$engine" image inspect --format '{{.Id}}' "$SHIELD_IMAGE")"
seed="${SHIELD_RANDOM_SEED:-0}"
changed_seed=$((seed + 1))
location=C.12580
calibration=container.smoke.repeatability
run_id="${GITHUB_RUN_ID:-local}-${GITHUB_RUN_ATTEMPT:-1}-$$"
containers=()
cleanup() {
  for name in "${containers[@]}"; do
    "$engine" unpause "$name" >/dev/null 2>&1 || true
    "$engine" rm -f "$name" >/dev/null 2>&1 || true
  done
}
trap cleanup EXIT
fail() { printf 'SHIELD replay check failed: %s\n' "$*" >&2; exit 1; }

arguments() {
  local root="$1" selected_seed="$2" mode="$3"
  docker_args=("${engine_args[@]}" --network none --user "$(id -u):$(id -g)"
    --mount "type=bind,src=$SHIELD_CACHE,dst=/work/cache,readonly$(mount_opts "$SHIELD_CACHE")"
    --mount "type=bind,src=$root,dst=/work/state$(mount_opts "$root")"
    --env "JHEEM_CENSUS_MANAGER_TAG=$CENSUS_TAG"
    --env "JHEEM_SYPHILIS_MANAGER_TAG=$SYPHILIS_TAG"
    --env SHIELD_ENABLE_CONTAINER_SMOKE=true --env SHIELD_CACHE_FREQUENCY=2
    --env SHIELD_UPDATE_FREQUENCY=1 --env "SHIELD_RANDOM_SEED=$selected_seed"
    --env "SHIELD_RUN_MODE=$mode" --env "SHIELD_IMAGE_ID=$image_id"
    --env SHIELD_OPERATOR=repeatability-check --env OPENBLAS_NUM_THREADS=1)
}

run_to_end() {
  local label="$1" root="$2" selected_seed="$3" mode="$4" status=0
  local name="shield-replay-$label-$run_id"
  containers+=("$name")
  arguments "$root" "$selected_seed" "$mode"
  "$engine" run --name "$name" "${docker_args[@]}" "$image_id" \
    calibrate "$location" "$calibration" >"$SHIELD_REPLAY_OUTPUT/$label.log" 2>&1 || status=$?
  if (( status != 0 )); then
    tail -60 "$SHIELD_REPLAY_OUTPUT/$label.log"
    fail "$label exited with status $status"
  fi
}

interrupt_after() {
  local mode="$1" target="$2" root="$SHIELD_REPLAY_OUTPUT/resumed"
  local name="shield-replay-interrupt$target-$run_id" ready=false polls=0
  local cache="$root/mcmc_runs/shield/$calibration/$location/cache"
  local chunk="$cache/chain_1/chain1_chunk$target.Rdata" control="$cache/chain1_control.Rdata"
  containers+=("$name")
  arguments "$root" "$seed" "$mode"
  "$engine" run --name "$name" "${docker_args[@]}" "$image_id" \
    calibrate "$location" "$calibration" >"$SHIELD_REPLAY_OUTPUT/interrupt$target.log" 2>&1 &
  local pid=$!
  while (( polls < 3600 )); do
    if [[ -f "$chunk" && -f "$control" && ! "$chunk" -nt "$control" ]]; then
      "$engine" pause "$name" >/dev/null || fail "could not pause $name"
      # Pausing prevents writes while a separate process verifies the cache.
      # Mount state read-only and give the verifier a separate report directory.
      if "$engine" run --rm "${engine_args[@]}" --network none --user "$(id -u):$(id -g)" \
        --mount "type=bind,src=$root,dst=/work/state,readonly$(mount_opts "$root")" \
        --mount "type=bind,src=$SHIELD_REPLAY_OUTPUT,dst=/reports$(mount_opts "$SHIELD_REPLAY_OUTPUT")" \
        "$image_id" shell -c \
        'Rscript "$JHEEM_ANALYSES_PATH/applications/SHIELD/tests/check-calibration-checkpoint.R" \
          /work/state "$1" "$2" "$3" "/reports/checkpoint$3.json"' \
        checkpoint "$location" "$calibration" "$target" \
        >"$SHIELD_REPLAY_OUTPUT/checkpoint$target.log" 2>&1; then
        ready=true
        "$engine" unpause "$name" >/dev/null
        "$engine" kill --signal KILL "$name" >/dev/null
        break
      fi
      "$engine" unpause "$name" >/dev/null
    fi
    kill -0 "$pid" 2>/dev/null || break
    polls=$((polls + 1))
    sleep 0.2
  done
  set +e
  wait "$pid"
  set -e
  if [[ "$ready" != true ]]; then
    tail -40 "$SHIELD_REPLAY_OUTPUT/interrupt$target.log"
    [[ ! -f "$SHIELD_REPLAY_OUTPUT/checkpoint$target.log" ]] || tail -20 "$SHIELD_REPLAY_OUTPUT/checkpoint$target.log"
    fail "could not verify checkpoint $target before interruption"
  fi
  # Verify that unpausing and killing did not advance or modify the checkpoint.
  python3 - "$SHIELD_REPLAY_OUTPUT/checkpoint$target.json" "$cache" <<'PY'
import hashlib, json, sys
from pathlib import Path
record = json.loads(Path(sys.argv[1]).read_text())
cache = Path(sys.argv[2])
assert hashlib.sha256((cache / 'chain1_control.Rdata').read_bytes()).hexdigest() == record['control_sha256']
for chunk in record['completed_chunks']:
    path = cache / 'chain_1' / f"chain1_chunk{chunk['chunk']}.Rdata"
    assert hashlib.sha256(path.read_bytes()).hexdigest() == chunk['sha256']
PY
  printf 'Stopped after verified checkpoint %s\n' "$target"
}

for label in fresh-a fresh-b resumed changed; do
  mkdir -p "$SHIELD_REPLAY_OUTPUT/$label/diagnostics"
done
run_to_end fresh-a "$SHIELD_REPLAY_OUTPUT/fresh-a" "$seed" fresh
run_to_end fresh-b "$SHIELD_REPLAY_OUTPUT/fresh-b" "$seed" fresh
interrupt_after fresh 1
interrupt_after resume 2
run_to_end resumed "$SHIELD_REPLAY_OUTPUT/resumed" "$seed" resume
run_to_end changed "$SHIELD_REPLAY_OUTPUT/changed" "$changed_seed" fresh

# Earlier completed chunks must still have their original bytes after resuming.
python3 - "$SHIELD_REPLAY_OUTPUT" "$calibration" "$location" <<'PY'
import hashlib, json, sys
from pathlib import Path
root, calibration, location = Path(sys.argv[1]), sys.argv[2], sys.argv[3]
cache = root / 'resumed' / 'mcmc_runs' / 'shield' / calibration / location / 'cache'
for target in (1, 2):
    record = json.loads((root / f'checkpoint{target}.json').read_text())
    for chunk in record['completed_chunks']:
        path = cache / 'chain_1' / f"chain1_chunk{chunk['chunk']}.Rdata"
        assert hashlib.sha256(path.read_bytes()).hexdigest() == chunk['sha256']
PY

for label in fresh-a fresh-b resumed changed; do
  root="$SHIELD_REPLAY_OUTPUT/$label"
  "$engine" run --rm "${engine_args[@]}" --network none --user "$(id -u):$(id -g)" \
    --mount "type=bind,src=$root,dst=/work/state,readonly$(mount_opts "$root")" \
    --mount "type=bind,src=$SHIELD_REPLAY_OUTPUT,dst=/reports$(mount_opts "$SHIELD_REPLAY_OUTPUT")" \
    "$image_id" shell -c \
    'Rscript "$JHEEM_ANALYSES_PATH/applications/SHIELD/tests/inspect-calibration-trace.R" \
      /work/state "$1" "$2" "/reports/$3-trace.json"' inspect "$location" "$calibration" "$label" \
    >"$SHIELD_REPLAY_OUTPUT/inspect-$label.log" 2>&1 \
    || { tail -40 "$SHIELD_REPLAY_OUTPUT/inspect-$label.log"; fail "$label trace inspection"; }
done
python3 "$scripts/compare_calibration_traces.py" \
  "$SHIELD_REPLAY_OUTPUT/fresh-a-trace.json" "$SHIELD_REPLAY_OUTPUT/fresh-b-trace.json" \
  "$SHIELD_REPLAY_OUTPUT/resumed-trace.json" "$SHIELD_REPLAY_OUTPUT/changed-trace.json" \
  "$SHIELD_REPLAY_OUTPUT/comparison.json"
