#!/usr/bin/env bash
# Completion, run-record, and pipeline check for the recorded SHIELD image.
#
# Runs after test_checkpoint_resume.sh on the same state, where
# container.smoke.stage0 has both chunks sampled but no summary or simulation
# set. Proves: a resumed run completes through the MCMC summary and assembly;
# every attempt leaves a record, and killed attempts stay "started";
# outputs.json matches the files on disk; and the pipeline command skips a
# completed stage and runs a later stage from it, naming that stage's recorded
# outputs in the later stage's inputs.
set -euo pipefail

: "${SHIELD_IMAGE:?SHIELD_IMAGE is required}"
: "${SHIELD_CACHE:?SHIELD_CACHE is required}"
: "${SHIELD_STATE:?SHIELD_STATE is required}"
: "${CENSUS_TAG:?CENSUS_TAG is required}"
: "${SYPHILIS_TAG:?SYPHILIS_TAG is required}"

location="C.12580"
stage0="container.smoke.stage0"
stage1="container.smoke.stage1"
run_id="${GITHUB_RUN_ID:-local}-${GITHUB_RUN_ATTEMPT:-1}"
diagnostics="$SHIELD_STATE/diagnostics"
mkdir -p "$diagnostics"

source "$(dirname "${BASH_SOURCE[0]}")/engine-env.sh"

image_id="$("$engine" image inspect --format '{{.Id}}' "$SHIELD_IMAGE")"
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
  --env "SHIELD_RANDOM_SEED=${SHIELD_RANDOM_SEED:-20260916}"
  --env "SHIELD_IMAGE_ID=$image_id"
  --env SHIELD_OPERATOR=canary
  --env "SHIELD_HOST=$(hostname -s 2>/dev/null || echo unknown)"
)

fail() {
  printf 'SHIELD records/pipeline test failed: %s\n' "$*" >&2
  exit 1
}

containers=()
cleanup() {
  for name in "${containers[@]}"; do
    "$engine" rm -f "$name" >/dev/null 2>&1 || true
  done
}
trap cleanup EXIT

# Run the image to completion; on failure show the log and whether it was OOM-killed.
run_to_end() {
  local label="$1"
  shift
  local name="shield-$label-$run_id" log="$diagnostics/$label.log" status=0
  containers+=("$name")
  "$engine" run --name "$name" "${docker_args[@]}" "$@" >"$log" 2>&1 || status=$?
  if (( status != 0 )); then
    "$engine" inspect --format 'OOMKilled={{.State.OOMKilled}} ExitCode={{.State.ExitCode}}' \
      "$name" 2>&1 | tee "$diagnostics/$label-state.txt" || true
    tail -60 "$log"
    fail "$label exited with status $status"
  fi
  printf '%s: finished\n' "$label"
}

# 1. Resume the interrupted canary to completion: summary, assembly, outputs.json.
run_to_end complete --env SHIELD_RUN_MODE=resume "$SHIELD_IMAGE" calibrate "$location" "$stage0"

# 2. A pipeline skips the completed stage and runs the next one from it.
run_to_end pipeline "$SHIELD_IMAGE" pipeline "$location" "$stage0" "$stage1"
grep -q "$stage0 for $location is already complete; skipping" "$diagnostics/pipeline.log" \
  || fail "pipeline did not skip the completed stage"

# 3. Running the finished pipeline again changes nothing.
run_to_end pipeline-again "$SHIELD_IMAGE" pipeline "$location" "$stage0" "$stage1"
[[ "$(grep -c 'already complete; skipping' "$diagnostics/pipeline-again.log")" -eq 2 ]] \
  || fail "a completed pipeline ran a stage again"

python3 - "$SHIELD_STATE" "$location" "$stage0" "$stage1" "$image_id" <<'EOF' || fail "run records are wrong"
import hashlib, json, sys
from pathlib import Path

state, location, stage0, stage1, image_id = sys.argv[1:]
records = Path(state) / "run_records" / "shield" / location

def sha256(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()

def attempts(stage):
    return [json.loads(p.read_text()) for p in sorted((records / stage / "attempts").glob("*.json"))]

def check(condition, message):
    if not condition:
        sys.exit(f"  {message}")

# Stage 0: killed fresh, killed resume, completed resume.
a0 = attempts(stage0)
check([(a["run_mode"], a["status"]) for a in a0] ==
      [("fresh", "started"), ("resume", "started"), ("resume", "succeeded")],
      f"{stage0} attempts: {[(a['run_mode'], a['status']) for a in a0]}")
check(all(a["image"]["id"] == image_id for a in a0), "attempt image id differs from the tested image")
check(a0[-1]["exit_code"] == 0 and a0[0]["exit_code"] is None, "attempt exit codes")

for stage in (stage0, stage1):
    outputs_file = records / stage / "outputs.json"
    check(outputs_file.is_file(), f"{stage} has no outputs.json")
    outputs = json.loads(outputs_file.read_text())
    inputs = json.loads((records / stage / "inputs.json").read_text())
    check(outputs["inputs"] == inputs["inputs"], f"{stage} outputs name different inputs")
    check(sorted(o["role"] for o in outputs["outputs"]) == ["mcmc_summary", "simulation_set"],
          f"{stage} output roles")
    for o in outputs["outputs"]:
        path = Path(state) / o["path"]
        check(path.is_file() and sha256(path) == o["sha256"] and path.stat().st_size == o["bytes"],
              f"{stage} {o['role']} does not match {o['path']}")
    check(attempts(stage)[-1]["receipts"]["outputs_sha256"] == sha256(outputs_file),
          f"{stage} final attempt does not name its outputs.json")
    print(f"  {stage}: " + ", ".join(f"{o['role']} {o['bytes'] / 1e6:.1f} MB" for o in outputs["outputs"]))

# Stage 1 starts from stage 0's recorded outputs and says so in its inputs.
stage1_inputs = json.loads((records / stage1 / "inputs.json").read_text())["inputs"]
check(stage1_inputs["preceding"] == [{"calibration_code": stage0,
                                      "outputs_sha256": sha256(records / stage0 / "outputs.json")}],
      f"{stage1} preceding: {stage1_inputs['preceding']}")
check(json.loads((records / stage0 / "inputs.json").read_text())["inputs"]["preceding"] == [],
      f"{stage0} should have no preceding stage")
a1 = attempts(stage1)
check([(a["run_mode"], a["status"]) for a in a1] == [("fresh", "succeeded")],
      f"{stage1} attempts: {[(a['run_mode'], a['status']) for a in a1]}")
EOF

# Read actual parameters and selected yearly outcomes, not only file digests.
# The inspector verifies recorded identities before deserializing; these are
# completed disposable canaries, never a live team's output files.
for stage in "$stage0" "$stage1"; do
  run_to_end "numeric-$stage" "$SHIELD_IMAGE" shell -c \
    'Rscript "$JHEEM_ANALYSES_PATH/applications/SHIELD/tests/inspect-recorded-outputs.R" \
      /work/state "$1" "$2" > "/work/state/diagnostics/numeric-$2.json"' \
    inspect "$location" "$stage"
done

# Negative checks change only the disposable canary state.
simset="$(python3 - "$SHIELD_STATE" "$location" "$stage0" <<'EOF'
import json, sys
from pathlib import Path
root, location, stage = sys.argv[1:]
record = json.loads((Path(root) / 'run_records' / 'shield' / location / stage / 'outputs.json').read_text())
print(Path(root) / next(o['path'] for o in record['outputs'] if o['role'] == 'simulation_set'))
EOF
)"
expect_rejected() {
  local label="$1" name status=0
  shift
  name="shield-reject-$label-$run_id"
  containers+=("$name")
  "$engine" run --name "$name" "${docker_args[@]}" "$@" \
    >"$diagnostics/rejected-$label.log" 2>&1 || status=$?
  (( status != 0 )) || fail "$label was incorrectly accepted as complete"
  grep -q 'failed verification' "$diagnostics/rejected-$label.log" \
    || { tail -30 "$diagnostics/rejected-$label.log"; fail "$label failed for the wrong reason"; }
}
mv "$simset" "$simset.test-backup"
expect_rejected missing "$SHIELD_IMAGE" pipeline "$location" "$stage0" "$stage1"
cp "$simset.test-backup" "$simset"
python3 - "$simset" <<'EOF'
import sys
with open(sys.argv[1], 'r+b') as artifact:
    first = artifact.read(1)
    artifact.seek(0)
    artifact.write(bytes([first[0] ^ 1]))
EOF
expect_rejected modified "$SHIELD_IMAGE" pipeline "$location" "$stage0" "$stage1"
mv "$simset.test-backup" "$simset"
expect_rejected seed --env SHIELD_RANDOM_SEED=1 "$SHIELD_IMAGE" pipeline "$location" "$stage0" "$stage1"
run_to_end pipeline-verified "$SHIELD_IMAGE" pipeline "$location" "$stage0" "$stage1"

printf 'SHIELD records/pipeline test passed, including negative reuse checks\n'
