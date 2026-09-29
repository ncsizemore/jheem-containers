#!/usr/bin/env bash
# Container checkpoint/resume canary for the recorded SHIELD image.
#
# Proves: the recorded image runs the real SHIELD model offline, writes a
# durable checkpoint, survives SIGKILL, and a separate resumed process continues
# from that checkpoint and writes the next one.
#
# Does not cover: the MCMC summary, simulation-set assembly, production-sized
# runs, or server storage and ownership. On a 16 GB hosted runner SHIELD peaks
# above the available memory while summarizing, so those are verified on a team
# server (see workloads/shield/README.md).
set -euo pipefail

: "${SHIELD_IMAGE:?SHIELD_IMAGE is required}"
: "${SHIELD_CACHE:?SHIELD_CACHE is required}"
: "${SHIELD_STATE:?SHIELD_STATE is required}"
: "${CENSUS_TAG:?CENSUS_TAG is required}"
: "${SYPHILIS_TAG:?SYPHILIS_TAG is required}"

location="C.12580"
calibration="container.smoke.stage0"
expected_chunks=2
run_id="${GITHUB_RUN_ID:-local}-${GITHUB_RUN_ATTEMPT:-1}"
# Layout of the pinned jheem2 (since jheem2@ccb1f9b): <version>/<calibration>/<location>.
calibration_dir="$SHIELD_STATE/mcmc_runs/shield/$calibration/$location"
cache_dir="$calibration_dir/cache"
chain_dir="$cache_dir/chain_1"
control_file="$cache_dir/chain1_control.Rdata"
diagnostics="$SHIELD_STATE/diagnostics"

mkdir -p "$SHIELD_STATE" "$diagnostics"

# Engine, rootless-podman options, and SELinux mount options (see engine-env.sh).
source "$(dirname "${BASH_SOURCE[0]}")/engine-env.sh"

docker_args=(
  "${engine_args[@]}"
  --network none
  --user "$(id -u):$(id -g)"
  --mount "type=bind,src=$SHIELD_CACHE,dst=/work/cache,readonly$(mount_opts "$SHIELD_CACHE")"
  --mount "type=bind,src=$SHIELD_STATE,dst=/work/state$(mount_opts "$SHIELD_STATE")"
  --env "JHEEM_CENSUS_MANAGER_TAG=$CENSUS_TAG"
  --env "JHEEM_SYPHILIS_MANAGER_TAG=$SYPHILIS_TAG"
  --env SHIELD_ENABLE_CONTAINER_SMOKE=true
  --env SHIELD_CACHE_FREQUENCY=1
  --env SHIELD_UPDATE_FREQUENCY=1
  --env SHIELD_RANDOM_SEED=20260916
)

fail() {
  printf 'SHIELD checkpoint test failed: %s\n' "$*" >&2
  exit 1
}

containers=()
cleanup() {
  for name in "${containers[@]}"; do
    "$engine" rm -f "$name" >/dev/null 2>&1 || true
  done
}
trap cleanup EXIT

chunk_count() {
  find "$chain_dir" -maxdepth 1 -type f -name 'chain1_chunk*.Rdata' 2>/dev/null | wc -l | tr -d ' '
}

# Run `calibrate` in the given mode until chunk N is durable, then SIGKILL it.
# The control file is saved immediately after each chunk (chain state and next
# seed). While the chunk is being written its mtime keeps moving past the
# control's, so a control that is not older than the chunk proves both are on
# disk. Kernel timestamps are coarse: the two saves can land in the same tick,
# so "newer" would miss the checkpoint (observed on shield2).
run_until_checkpoint() {
  local mode="$1" chunk="$2"
  local name="shield-$mode-$run_id"
  local chunk_file="$chain_dir/chain1_chunk${chunk}.Rdata"
  local log="$diagnostics/$mode.log"
  local memory="$diagnostics/$mode-memory.txt"
  containers+=("$name")

  "$engine" run "${docker_args[@]}" --name "$name" --env "SHIELD_RUN_MODE=$mode" \
    "$SHIELD_IMAGE" calibrate "$location" "$calibration" >"$log" 2>&1 &
  local pid=$!

  local ready=false polls=0
  while (( polls < 3000 )); do
    if [[ -f "$chunk_file" && -f "$control_file" && ! "$chunk_file" -nt "$control_file" ]]; then
      ready=true
      break
    fi
    if ! kill -0 "$pid" 2>/dev/null; then
      break
    fi
    if (( polls % 75 == 0 )); then
      printf '%s %s\n' "$(date -u +%H:%M:%S)" \
        "$("$engine" stats --no-stream --format '{{.MemUsage}}' "$name" 2>/dev/null || echo n/a)" >>"$memory"
    fi
    polls=$((polls + 1))
    sleep 0.2
  done

  if [[ "$ready" != true ]]; then
    "$engine" inspect --format 'OOMKilled={{.State.OOMKilled}} ExitCode={{.State.ExitCode}}' \
      "$name" >"$diagnostics/$mode-state.txt" 2>&1 || true
    cat "$diagnostics/$mode-state.txt" "$log"
    fail "$mode run stopped or timed out before chunk $chunk was durable"
  fi

  "$engine" kill --signal KILL "$name" >/dev/null 2>&1 || true
  set +e
  wait "$pid"
  set -e
  printf '%s run: chunk %s durable; peak sampled memory %s\n' "$mode" "$chunk" \
    "$(awk '{print $2}' "$memory" 2>/dev/null | sort -h | tail -1)"
}

# 1. A fresh recorded run sets up and samples; stop it after its first checkpoint.
run_until_checkpoint fresh 1
chunks_before_resume=$(chunk_count)
[[ "$chunks_before_resume" -eq 1 ]] \
  || fail "expected 1 of $expected_chunks chunks after interruption; found $chunks_before_resume"
chunk1_sha=$(sha256sum "$chain_dir/chain1_chunk1.Rdata" | cut -d' ' -f1)

# 2. A separate resumed process continues from that checkpoint and writes the next.
run_until_checkpoint resume "$expected_chunks"
chunks_after_resume=$(chunk_count)
[[ "$chunks_after_resume" -eq "$expected_chunks" ]] \
  || fail "resume produced $chunks_after_resume of $expected_chunks chunks"
# Resume must continue, not restart: the first checkpoint is left untouched.
[[ "$(sha256sum "$chain_dir/chain1_chunk1.Rdata" | cut -d' ' -f1)" == "$chunk1_sha" ]] \
  || fail "resume rewrote the first checkpoint instead of continuing from it"

printf 'SHIELD checkpoint/resume test passed: %s -> %s chunks\n' \
  "$chunks_before_resume" "$chunks_after_resume"
