#!/usr/bin/env bash
# Server pilot: run one recorded calibration without interruption, through the
# MCMC summary and simulation-set assembly, recording time, memory, and chunk
# timings. Defaults to the two-iteration canary; set SHIELD_CALIBRATION and
# SHIELD_LOCATION for a real stage. Not part of hosted CI: the summary exceeds a
# 16 GB runner's memory. SHIELD_STATE must be empty.
#
# Progress and the final result are written to <state>/pilot-full-run/STATUS,
# so a detached run can be checked later without the launching session.
set -euo pipefail

: "${SHIELD_IMAGE:?SHIELD_IMAGE is required}"
: "${SHIELD_CACHE:?SHIELD_CACHE is required}"
: "${SHIELD_STATE:?SHIELD_STATE is required}"
: "${CENSUS_TAG:?CENSUS_TAG is required}"
: "${SYPHILIS_TAG:?SYPHILIS_TAG is required}"

location="${SHIELD_LOCATION:-C.12580}"
calibration="${SHIELD_CALIBRATION:-container.smoke.stage0}"
smoke=false
[[ "$calibration" == container.smoke.* ]] && smoke=true
# The canary checkpoints every iteration; real stages default to the ordinary
# launcher's frequencies (cache 500, update 50).
cache_frequency="${SHIELD_CACHE_FREQUENCY:-$([[ $smoke == true ]] && echo 1 || echo 500)}"
update_frequency="${SHIELD_UPDATE_FREQUENCY:-$([[ $smoke == true ]] && echo 1 || echo 50)}"
sample_seconds="${SHIELD_SAMPLE_SECONDS:-$([[ $smoke == true ]] && echo 10 || echo 60)}"

CONTAINER_ENGINE="${CONTAINER_ENGINE:-podman}"
# Engine, rootless-podman options, and SELinux mount options (see engine-env.sh).
source "$(dirname "${BASH_SOURCE[0]}")/engine-env.sh"
name="shield-pilot-full-$(date -u +%Y%m%dT%H%M%S)"
report="$SHIELD_STATE/pilot-full-run"

mkdir -p "$SHIELD_STATE"
if find "$SHIELD_STATE" -mindepth 1 -maxdepth 1 | grep -q .; then
  echo "SHIELD_STATE must be empty for a fresh pilot run: $SHIELD_STATE" >&2
  exit 1
fi
mkdir -p "$report"

status() { printf '%s %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*" >>"$report/STATUS"; }
status "started: $calibration $location on $(hostname) container=$name image=$SHIELD_IMAGE"

run_env=(
  --env "JHEEM_CENSUS_MANAGER_TAG=$CENSUS_TAG"
  --env "JHEEM_SYPHILIS_MANAGER_TAG=$SYPHILIS_TAG"
  --env "SHIELD_CACHE_FREQUENCY=$cache_frequency"
  --env "SHIELD_UPDATE_FREQUENCY=$update_frequency"
  --env SHIELD_RANDOM_SEED=20260916
  --env SHIELD_RUN_MODE=fresh
  # One BLAS thread per R process, as the team's launchers set.
  --env OPENBLAS_NUM_THREADS=1
)
[[ "$smoke" == true ]] && run_env+=(--env SHIELD_ENABLE_CONTAINER_SMOKE=true)

start=$(date +%s)
"$engine" run "${engine_args[@]}" --name "$name" \
  --network none \
  --user "$(id -u):$(id -g)" \
  --mount "type=bind,src=$SHIELD_CACHE,dst=/work/cache,readonly$(mount_opts "$SHIELD_CACHE")" \
  --mount "type=bind,src=$SHIELD_STATE,dst=/work/state$(mount_opts "$SHIELD_STATE")" \
  "${run_env[@]}" \
  "$SHIELD_IMAGE" calibrate "$location" "$calibration" >"$report/run.log" 2>&1 &
pid=$!

while kill -0 "$pid" 2>/dev/null; do
  printf '%s %s\n' "$(date -u +%H:%M:%S)" \
    "$("$engine" stats --no-stream --format '{{.MemUsage}}' "$name" 2>/dev/null || echo n/a)" \
    >>"$report/memory.txt"
  sleep "$sample_seconds"
done
set +e
wait "$pid"
status_code=$?
set -e
elapsed=$(( $(date +%s) - start ))
"$engine" inspect --format 'OOMKilled={{.State.OOMKilled}} ExitCode={{.State.ExitCode}}' \
  "$name" >"$report/container-state.txt" 2>&1 || true
"$engine" rm -f "$name" >/dev/null 2>&1 || true

# Layout of the pinned jheem2 (since jheem2@ccb1f9b): <version>/<calibration>/<location>.
chain_dir="$SHIELD_STATE/mcmc_runs/shield/$calibration/$location/cache/chain_1"
ls -l --time-style=+%Y-%m-%dT%H:%M:%S "$chain_dir" 2>/dev/null \
  | awk 'NR > 1 {print $6, $5, $7}' | sort >"$report/chunks.txt" || true
summary="$SHIELD_STATE/mcmc_summaries/shield/$calibration/summary_shield_${location}_${calibration}.Rdata"
simsets=$(find "$SHIELD_STATE/simulations" -type f -name '*.Rdata' 2>/dev/null | wc -l | tr -d ' ')
peak=$(awk '{print $2}' "$report/memory.txt" | grep -v n/a | sort -h | tail -1)

{
  echo "calibration: $calibration $location"
  echo "image: $SHIELD_IMAGE"
  echo "engine: $engine $("$engine" --version 2>/dev/null | head -1)"
  echo "host: $(hostname)"
  echo "exit status: $status_code"
  cat "$report/container-state.txt"
  echo "elapsed seconds: $elapsed"
  echo "peak sampled memory: ${peak:-n/a}"
  echo "chunks written: $(wc -l <"$report/chunks.txt" | tr -d ' ')"
  echo "summary file: $([[ -s "$summary" ]] && echo present || echo missing)"
  echo "simulation-set files: $simsets"
} | tee "$report/summary.txt"

if [[ "$status_code" -eq 0 && -s "$summary" && "$simsets" -ge 1 ]]; then
  status "finished: exit 0, ${elapsed}s, peak ${peak:-n/a}"
  echo "Pilot full run completed; report in $report"
else
  status "failed: exit $status_code, ${elapsed}s, peak ${peak:-n/a} (see run.log)"
  echo "Pilot full run did not complete; see $report" >&2
  tail -30 "$report/run.log" >&2
  exit 1
fi
