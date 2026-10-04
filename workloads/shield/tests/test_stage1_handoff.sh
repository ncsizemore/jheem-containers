#!/usr/bin/env bash
# Two-iteration copies of the real stage-0 and stage-1 registrations. Separate
# disposable state; no production registration, likelihood, or sampler change.
set -euo pipefail
: "${SHIELD_IMAGE:?SHIELD_IMAGE is required}"
: "${SHIELD_CACHE:?SHIELD_CACHE is required}"
: "${SHIELD_HANDOFF_STATE:?SHIELD_HANDOFF_STATE is required}"
: "${CENSUS_TAG:?CENSUS_TAG is required}"
: "${SYPHILIS_TAG:?SYPHILIS_TAG is required}"
scripts="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$scripts/engine-env.sh"
[[ ! -e "$SHIELD_HANDOFF_STATE" ]] || { echo 'Handoff state must be a new directory' >&2; exit 1; }
mkdir -p "$SHIELD_HANDOFF_STATE/diagnostics"
image_id="$("$engine" image inspect --format '{{.Id}}' "$SHIELD_IMAGE")"
args=("${engine_args[@]}" --network none --user "$(id -u):$(id -g)"
  --mount "type=bind,src=$SHIELD_CACHE,dst=/work/cache,readonly$(mount_opts "$SHIELD_CACHE")"
  --mount "type=bind,src=$SHIELD_HANDOFF_STATE,dst=/work/state$(mount_opts "$SHIELD_HANDOFF_STATE")"
  --env "JHEEM_CENSUS_MANAGER_TAG=$CENSUS_TAG"
  --env "JHEEM_SYPHILIS_MANAGER_TAG=$SYPHILIS_TAG"
  --env "SHIELD_RANDOM_SEED=${SHIELD_RANDOM_SEED:-0}"
  --env SHIELD_ENABLE_CONTAINER_SMOKE=true --env SHIELD_CACHE_FREQUENCY=1
  --env SHIELD_UPDATE_FREQUENCY=1 --env OPENBLAS_NUM_THREADS=1
  --env "SHIELD_IMAGE_ID=$image_id" --env SHIELD_OPERATOR=stage1-handoff-check)
run_check() {
  local label="$1"
  shift
  if ! "$engine" run --rm "${args[@]}" "$image_id" "$@" \
    >"$SHIELD_HANDOFF_STATE/diagnostics/$label.log" 2>&1; then
    tail -60 "$SHIELD_HANDOFF_STATE/diagnostics/$label.log"
    echo "Stage-1 handoff check failed: $label" >&2
    exit 1
  fi
  printf '%s: passed\n' "$label"
}
run_check actual-pipeline pipeline C.12580 container.actual.stage0 container.actual.stage1
run_check inspect-handoff shell -c \
  'Rscript "$JHEEM_ANALYSES_PATH/applications/SHIELD/tests/inspect-stage1-handoff.R" \
    /work/state C.12580 /work/state/diagnostics/handoff.json'
for stage in container.actual.stage0 container.actual.stage1; do
  run_check "numeric-$stage" shell -c \
    'Rscript "$JHEEM_ANALYSES_PATH/applications/SHIELD/tests/inspect-recorded-outputs.R" \
      /work/state C.12580 "$1" "/work/state/diagnostics/numeric-$1.json"' inspect "$stage"
done
run_check completed-pipeline pipeline C.12580 container.actual.stage0 container.actual.stage1
[[ "$(grep -c 'already complete; skipping' "$SHIELD_HANDOFF_STATE/diagnostics/completed-pipeline.log")" -eq 2 ]] \
  || { echo 'Completed actual stages were not both verified and skipped' >&2; exit 1; }
python3 - "$SHIELD_HANDOFF_STATE/diagnostics" <<'PY'
import json, sys
from pathlib import Path
root = Path(sys.argv[1])
report = json.loads((root / 'handoff.json').read_text())
assert report['status'] == 'passed' and report['predecessor_parameters_copied'] > 0
assert [s['calibration_code'] for s in report['stages']] == ['container.actual.stage0', 'container.actual.stage1']
for stage in report['stages']:
    numeric = json.loads((root / f"numeric-{stage['calibration_code']}.json").read_text())
    assert stage['iterations'] == 2 and numeric['n_sim'] == 2
    assert numeric['calibration_code'] == stage['calibration_code']
    assert numeric['parameter_count'] == report['predecessor_parameters_copied']
print(f"Actual stage-1 handoff passed; {report['predecessor_parameters_copied']} parameters copied")
PY
