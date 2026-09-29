#!/usr/bin/env bash
# Server pilot: run the canary calibration once without interruption, through
# the MCMC summary and simulation-set assembly, recording peak memory and time.
# Not part of hosted CI: the summary exceeds a 16 GB runner's memory. Uses the
# same variables as test_checkpoint_resume.sh; SHIELD_STATE must be empty.
set -euo pipefail

: "${SHIELD_IMAGE:?SHIELD_IMAGE is required}"
: "${SHIELD_CACHE:?SHIELD_CACHE is required}"
: "${SHIELD_STATE:?SHIELD_STATE is required}"
: "${CENSUS_TAG:?CENSUS_TAG is required}"
: "${SYPHILIS_TAG:?SYPHILIS_TAG is required}"

location="C.12580"
calibration="container.smoke.stage0"
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

start=$(date +%s)
"$engine" run "${engine_args[@]}" --name "$name" \
  --network none \
  --user "$(id -u):$(id -g)" \
  --mount "type=bind,src=$SHIELD_CACHE,dst=/work/cache,readonly$(mount_opts "$SHIELD_CACHE")" \
  --mount "type=bind,src=$SHIELD_STATE,dst=/work/state$(mount_opts "$SHIELD_STATE")" \
  --env "JHEEM_CENSUS_MANAGER_TAG=$CENSUS_TAG" \
  --env "JHEEM_SYPHILIS_MANAGER_TAG=$SYPHILIS_TAG" \
  --env SHIELD_ENABLE_CONTAINER_SMOKE=true \
  --env SHIELD_CACHE_FREQUENCY=1 \
  --env SHIELD_UPDATE_FREQUENCY=1 \
  --env SHIELD_RANDOM_SEED=20260916 \
  --env SHIELD_RUN_MODE=fresh \
  "$SHIELD_IMAGE" calibrate "$location" "$calibration" >"$report/run.log" 2>&1 &
pid=$!

while kill -0 "$pid" 2>/dev/null; do
  printf '%s %s\n' "$(date -u +%H:%M:%S)" \
    "$("$engine" stats --no-stream --format '{{.MemUsage}}' "$name" 2>/dev/null || echo n/a)" \
    >>"$report/memory.txt"
  sleep 10
done
set +e
wait "$pid"
status=$?
set -e
elapsed=$(( $(date +%s) - start ))
"$engine" inspect --format 'OOMKilled={{.State.OOMKilled}} ExitCode={{.State.ExitCode}}' \
  "$name" >"$report/container-state.txt" 2>&1 || true
"$engine" rm -f "$name" >/dev/null 2>&1 || true

summary="$SHIELD_STATE/mcmc_summaries/shield/$calibration/summary_shield_${location}_${calibration}.Rdata"
simsets=$(find "$SHIELD_STATE/simulations" -type f -name '*.Rdata' 2>/dev/null | wc -l | tr -d ' ')
peak=$(awk '{print $2}' "$report/memory.txt" | grep -v n/a | sort -h | tail -1)

{
  echo "image: $SHIELD_IMAGE"
  echo "engine: $engine $("$engine" --version 2>/dev/null | head -1)"
  echo "host: $(hostname)"
  echo "exit status: $status"
  cat "$report/container-state.txt"
  echo "elapsed seconds: $elapsed"
  echo "peak sampled memory: ${peak:-n/a}"
  echo "summary file: $([[ -s "$summary" ]] && echo present || echo missing)"
  echo "simulation-set files: $simsets"
} | tee "$report/summary.txt"

[[ "$status" -eq 0 && -s "$summary" && "$simsets" -ge 1 ]] || {
  echo "Pilot full run did not complete; see $report" >&2
  tail -30 "$report/run.log" >&2
  exit 1
}
echo "Pilot full run completed; report in $report"
