#!/usr/bin/env bash
set -euo pipefail

: "${SHIELD_IMAGE:?SHIELD_IMAGE is required}"
: "${SHIELD_CACHE:?SHIELD_CACHE is required}"
: "${SHIELD_STATE:?SHIELD_STATE is required}"
: "${CENSUS_TAG:?CENSUS_TAG is required}"
: "${SYPHILIS_TAG:?SYPHILIS_TAG is required}"

location="C.12580"
calibration="container.smoke.stage0"
expected_chunks=2
container_name="shield-checkpoint-${GITHUB_RUN_ID:-local}-${GITHUB_RUN_ATTEMPT:-1}"
calibration_dir="$SHIELD_STATE/mcmc_runs/shield/$location/$calibration"
cache_dir="$calibration_dir/cache"
chain_dir="$cache_dir/chain_1"
control_file="$cache_dir/chain1_control.Rdata"
first_chunk="$chain_dir/chain1_chunk1.Rdata"
last_chunk="$chain_dir/chain1_chunk${expected_chunks}.Rdata"
summary_file="$SHIELD_STATE/mcmc_summaries/shield/$calibration/summary_shield_${location}_${calibration}.Rdata"
interrupted_log="$SHIELD_STATE/interrupted-calibration.log"

mkdir -p "$SHIELD_STATE"

docker_args=(
  --rm
  --network none
  --user "$(id -u):$(id -g)"
  --mount "type=bind,src=$SHIELD_CACHE,dst=/work/cache,readonly"
  --mount "type=bind,src=$SHIELD_STATE,dst=/work/state"
  --env "JHEEM_CENSUS_MANAGER_TAG=$CENSUS_TAG"
  --env "JHEEM_SYPHILIS_MANAGER_TAG=$SYPHILIS_TAG"
  --env SHIELD_ENABLE_CONTAINER_SMOKE=true
  --env SHIELD_CACHE_FREQUENCY=1
  --env SHIELD_UPDATE_FREQUENCY=1
  --env SHIELD_RANDOM_SEED=20260916
)

run_stage() {
  local run_mode="$1"
  shift
  docker run "${docker_args[@]}" \
    --env "SHIELD_RUN_MODE=$run_mode" \
    "$SHIELD_IMAGE" "$@"
}

fail() {
  printf 'SHIELD checkpoint test failed: %s\n' "$*" >&2
  exit 1
}

cleanup() {
  docker rm -f "$container_name" >/dev/null 2>&1 || true
}
trap cleanup EXIT

run_stage fresh calibration-stage "$location" "$calibration" setup 1

docker run "${docker_args[@]}" \
  --name "$container_name" \
  --env SHIELD_RUN_MODE=resume \
  "$SHIELD_IMAGE" \
  calibration-stage "$location" "$calibration" run 1 \
  >"$interrupted_log" 2>&1 &
interrupted_pid=$!

checkpoint_ready=false
for _ in $(seq 1 3000); do
  if ! kill -0 "$interrupted_pid" 2>/dev/null; then
    set +e
    wait "$interrupted_pid"
    interrupted_status=$?
    set -e
    cat "$interrupted_log"
    fail "calibration exited with status $interrupted_status before interruption"
  fi

  # The control is saved immediately after the chunk. Waiting until it is newer
  # proves that the completed chunk, updated chain state, and next seed are all
  # durable before sending SIGKILL.
  if [[ -f "$first_chunk" && "$control_file" -nt "$first_chunk" ]]; then
    checkpoint_ready=true
    break
  fi
  sleep 0.2
done

if [[ "$checkpoint_ready" != true ]]; then
  cat "$interrupted_log"
  fail "no durable checkpoint appeared within 10 minutes"
fi

docker kill --signal KILL "$container_name" >/dev/null
set +e
wait "$interrupted_pid"
interrupted_status=$?
set -e

if [[ "$interrupted_status" -eq 0 ]]; then
  fail "forced interruption unexpectedly exited successfully"
fi

chunks_before_resume=$(find "$chain_dir" -maxdepth 1 -type f -name 'chain1_chunk*.Rdata' | wc -l | tr -d ' ')
if [[ "$chunks_before_resume" -lt 1 || "$chunks_before_resume" -ge "$expected_chunks" ]]; then
  cat "$interrupted_log"
  fail "expected a partial checkpoint; found $chunks_before_resume of $expected_chunks chunks"
fi
printf 'Forced termination preserved %s of %s chunks; resuming\n' \
  "$chunks_before_resume" "$expected_chunks"

run_stage resume calibration-stage "$location" "$calibration" run 1

[[ -f "$last_chunk" ]] || fail "resume did not complete the final checkpoint chunk"
chunks_after_resume=$(find "$chain_dir" -maxdepth 1 -type f -name 'chain1_chunk*.Rdata' | wc -l | tr -d ' ')
[[ "$chunks_after_resume" -eq "$expected_chunks" ]] \
  || fail "resume produced $chunks_after_resume of $expected_chunks chunks"
[[ -s "$summary_file" ]] || fail "completed calibration did not produce an MCMC summary"

printf 'SHIELD checkpoint/resume test passed: %s -> %s chunks\n' \
  "$chunks_before_resume" "$chunks_after_resume"
