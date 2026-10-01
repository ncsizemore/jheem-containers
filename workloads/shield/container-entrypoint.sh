#!/usr/bin/env sh
set -eu

fail() {
  printf 'SHIELD container error: %s\n' "$*" >&2
  exit 64
}

if [ "$(id -u)" = "0" ] && [ "${SHIELD_ALLOW_ROOT:-false}" != "true" ]; then
  fail "refusing to run as root; pass --user with the host UID:GID (or explicitly set SHIELD_ALLOW_ROOT=true for a disposable test)"
fi

# Numeric host identities often have no passwd entry in the image. Give R and
# renv a writable, process-local home instead of allowing fallback writes under
# /root or the baked project tree.
runtime_home="${SHIELD_RUNTIME_HOME:-/tmp/shield-home-$(id -u)}"
mkdir -p "$runtime_home" || fail "cannot create runtime home: $runtime_home"
export HOME="$runtime_home"
export R_USER="$runtime_home"

# The names recorded mode accepts, which are also safe in paths and JSON.
check_name() {
  case "$1" in
    '' | [!A-Za-z0-9]* | *[!A-Za-z0-9._-]*) fail "not a valid location or calibration code: '$1'" ;;
  esac
}

# Free-form values (operator, host, image) reduced to JSON-safe text.
clean() {
  printf '%s' "${1:-unknown}" | tr -c 'A-Za-z0-9._:@+-' '_'
}

quoted_or_null() {
  if [ -n "$1" ]; then printf '"%s"' "$1"; else printf 'null'; fi
}

sha256_or_empty() {
  if [ -f "$1" ]; then sha256sum "$1" | cut -d' ' -f1; fi
}

records_dir() {
  printf '%s/run_records/shield/%s/%s' "$JHEEM_ROOT_DIR" "$1" "$2"
}

# One record per attempt (a fresh start or a resume), beside the calibration's
# inputs.json and outputs.json. It is written as "started" before any work and
# rewritten when the attempt ends; a record left at "started" after its
# container has gone was interrupted (stopped, killed, or lost with the host).
write_attempt() {
  attempt_status="$1" attempt_exit="$2" attempt_finished="$3"
  cat >"$attempt_file.tmp" <<EOF
{
  "schema_version": 1,
  "location": "$stage_location",
  "calibration_code": "$stage_calibration",
  "run_mode": "$stage_mode",
  "status": "$attempt_status",
  "exit_code": $attempt_exit,
  "started_at_utc": "$attempt_started",
  "finished_at_utc": $(quoted_or_null "$attempt_finished"),
  "operator": {"user": "$(clean "${SHIELD_OPERATOR:-uid-$(id -u)}")", "host": "$(clean "${SHIELD_HOST:-}")"},
  "image": {"id": "$(clean "${SHIELD_IMAGE_ID:-}")", "profile": "$(clean "${SHIELD_CONTAINER_PROFILE:-}")"},
  "sources": {
    "jheem_analyses": "$(clean "${JHEEM_ANALYSES_REF:-}")",
    "jheem2": "$(clean "${JHEEM2_REF:-}")",
    "locations": "$(clean "${LOCATIONS_REF:-}")",
    "bayesian_simulations": "$(clean "${BAYESIAN_SIMULATIONS_REF:-}")",
    "distributions": "$(clean "${DISTRIBUTIONS_REF:-}")"
  },
  "settings": {
    "census_manager_tag": "$(clean "${JHEEM_CENSUS_MANAGER_TAG:-}")",
    "syphilis_manager_tag": "$(clean "${JHEEM_SYPHILIS_MANAGER_TAG:-}")",
    "random_seed": "$(clean "${SHIELD_RANDOM_SEED:-}")",
    "cache_frequency": "$(clean "${SHIELD_CACHE_FREQUENCY:-500}")",
    "update_frequency": "$(clean "${SHIELD_UPDATE_FREQUENCY:-50}")",
    "openblas_num_threads": "$(clean "${OPENBLAS_NUM_THREADS:-}")"
  },
  "receipts": {
    "inputs_sha256": $(quoted_or_null "$(sha256_or_empty "$stage_records/inputs.json")"),
    "outputs_sha256": $(quoted_or_null "$(sha256_or_empty "$stage_records/outputs.json")")
  }
}
EOF
  mv "$attempt_file.tmp" "$attempt_file" || fail "cannot write attempt record: $attempt_file"
}

# Run one calibration stage in the given mode and record the attempt. Returns
# the exit status of preflight or the SHIELD launcher.
run_stage() {
  stage_location="$1" stage_calibration="$2" stage_mode="$3"
  stage_records="$(records_dir "$stage_location" "$stage_calibration")"
  mkdir -p "$stage_records/attempts" || fail "cannot create $stage_records/attempts"
  attempt_started="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  attempt_base="$stage_records/attempts/$(date -u +%Y%m%dT%H%M%SZ)-$stage_mode"
  attempt_file="$attempt_base.json"
  attempt_n=2
  while [ -e "$attempt_file" ]; do
    attempt_file="$attempt_base-$attempt_n.json"
    attempt_n=$((attempt_n + 1))
  done
  write_attempt started null ""

  export SHIELD_RUN_MODE="$stage_mode"
  stage_exit=0
  Rscript /opt/shield/preflight.R \
    && Rscript "${JHEEM_ANALYSES_PATH}/applications/SHIELD/shield_calib_setup_and_run.R" \
      "$stage_location" "$stage_calibration" \
    || stage_exit=$?

  if [ "$stage_exit" -eq 0 ]; then stage_status=succeeded; else stage_status=failed; fi
  write_attempt "$stage_status" "$stage_exit" "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  return "$stage_exit"
}

command_name="${1:-preflight}"

case "$command_name" in
  shell)
    shift
    exec "${SHELL:-/bin/bash}" "$@"
    ;;
  preflight)
    exec Rscript /opt/shield/preflight.R
    ;;
  calibrate)
    [ "$#" -eq 3 ] || fail "usage: calibrate <location> <calibration-code>"
    check_name "$2"
    check_name "$3"
    code=0
    run_stage "$2" "$3" "${SHIELD_RUN_MODE:-resume}" || code=$?
    exit "$code"
    ;;
  pipeline)
    # Stages run in order, each after the previous one completes. Running the
    # same pipeline again continues it: a stage with recorded outputs is
    # skipped, a started stage is resumed, and the rest start fresh.
    [ "$#" -ge 3 ] || fail "usage: pipeline <location> <calibration-code>..."
    shift
    location="$1"
    shift
    check_name "$location"
    for calibration in "$@"; do check_name "$calibration"; done
    for calibration in "$@"; do
      records="$(records_dir "$location" "$calibration")"
      if [ -f "$records/outputs.json" ]; then
        Rscript "${JHEEM_ANALYSES_PATH}/applications/SHIELD/check_recorded_completion.R" \
          "$location" "$calibration" \
          || fail "completed stage $calibration failed verification; no stages were repaired or cleared"
        printf 'SHIELD pipeline: %s for %s is already complete; skipping\n' "$calibration" "$location"
        continue
      fi
      if [ -f "$records/inputs.json" ]; then mode=resume; else mode=fresh; fi
      printf 'SHIELD pipeline: %s for %s (%s)\n' "$calibration" "$location" "$mode"
      code=0
      run_stage "$location" "$calibration" "$mode" || code=$?
      if [ "$code" -ne 0 ]; then
        printf 'SHIELD pipeline: %s for %s failed (exit %s); later stages not run\n' \
          "$calibration" "$location" "$code" >&2
        exit "$code"
      fi
    done
    printf 'SHIELD pipeline: all stages complete for %s\n' "$location"
    ;;
  *)
    fail "unknown command '$command_name' (expected preflight, calibrate, pipeline, or shell)"
    ;;
esac
