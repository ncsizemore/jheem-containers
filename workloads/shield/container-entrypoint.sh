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

# One record per attempt (one R process: a setup, a chain, an assembly, or a
# single-process stage), beside the calibration's inputs.json and outputs.json.
# It is written as "started" before any work and rewritten when the attempt
# ends; a record left at "started" after its container has gone was interrupted
# (stopped, killed, or lost with the host).
write_attempt() {
  attempt_status="$1" attempt_exit="$2" attempt_finished="$3"
  cat >"$attempt_file.tmp" <<EOF
{
  "schema_version": 1,
  "location": "$stage_location",
  "calibration_code": "$stage_calibration",
  "run_mode": "$stage_mode",
  "phase": "$stage_phase",
  "chain": $(if [ -n "$stage_chain" ]; then printf '%s' "$stage_chain"; else printf null; fi),
  "status": "$attempt_status",
  "exit_code": $attempt_exit,
  "started_at_utc": "$attempt_started",
  "finished_at_utc": $(quoted_or_null "$attempt_finished"),
  "operator": {"user": "$(clean "${SHIELD_OPERATOR:-uid-$(id -u)}")", "host": "$(clean "${SHIELD_HOST:-}")"},
  "image": {"id": "$(clean "${SHIELD_IMAGE_ID:-}")", "profile": "$(clean "${SHIELD_CONTAINER_PROFILE:-}")"},
  "runner": {"entrypoint_sha256": "$entrypoint_sha256"},
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

entrypoint_sha256="$(sha256_or_empty "$0")"

# Run one recorded R process (preflight, then the SHIELD launcher) for a phase,
# and record it as an attempt. Arguments: location, calibration, run mode,
# phase (all, setup, run, assemble), chain (or empty), and an optional log file
# (empty: this container's output). Returns the R exit status.
run_phase() {
  stage_location="$1" stage_calibration="$2" stage_mode="$3" stage_phase="$4" stage_chain="$5"
  phase_log="${6:-}"
  stage_records="$(records_dir "$stage_location" "$stage_calibration")"
  mkdir -p "$stage_records/attempts" || fail "cannot create $stage_records/attempts"
  attempt_started="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  case "$stage_phase" in
    all) attempt_label="$stage_mode" ;;
    run) attempt_label="chain$stage_chain" ;;
    *) attempt_label="$stage_phase" ;;
  esac
  attempt_base="$stage_records/attempts/$(date -u +%Y%m%dT%H%M%SZ)-$attempt_label"
  attempt_file="$attempt_base.json"
  attempt_n=2
  while [ -e "$attempt_file" ]; do
    attempt_file="$attempt_base-$attempt_n.json"
    attempt_n=$((attempt_n + 1))
  done
  write_attempt started null ""

  stage_exit=0
  if [ -n "$phase_log" ]; then
    SHIELD_RUN_MODE="$stage_mode" SHIELD_RECORDED_PHASE="$stage_phase" SHIELD_RECORDED_CHAIN="$stage_chain" \
      launch_r "$stage_location" "$stage_calibration" >"$phase_log" 2>&1 || stage_exit=$?
  else
    SHIELD_RUN_MODE="$stage_mode" SHIELD_RECORDED_PHASE="$stage_phase" SHIELD_RECORDED_CHAIN="$stage_chain" \
      launch_r "$stage_location" "$stage_calibration" || stage_exit=$?
  fi

  if [ "$stage_exit" -eq 0 ]; then stage_status=succeeded; else stage_status=failed; fi
  write_attempt "$stage_status" "$stage_exit" "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  return "$stage_exit"
}

launch_r() {
  Rscript /opt/shield/preflight.R \
    && Rscript "${JHEEM_ANALYSES_PATH}/applications/SHIELD/shield_calib_setup_and_run.R" "$1" "$2"
}

# Analysis code from before phased runs has only the single-process launcher.
phased_source() {
  grep -q '^shield.recorded.phase <- function' \
    "${JHEEM_ANALYSES_PATH}/applications/SHIELD/R/shield_recorded_runtime.R" 2>/dev/null
}

# Run (or continue) one calibration stage: setup when starting, then every
# chain, then assembly. Chains run in parallel, at most SHIELD_MAX_PARALLEL_CHAINS
# at a time (default: all), each logging to run_records/.../logs/. A chain that
# fails stops the stage before assembly; running the stage again continues each
# chain from its last checkpoint.
run_stage() {
  location="$1" calibration="$2" mode="$3"
  if ! phased_source; then
    run_phase "$location" "$calibration" "$mode" all "" ""
    return
  fi
  records="$(records_dir "$location" "$calibration")"
  if [ "$mode" = fresh ]; then
    run_phase "$location" "$calibration" fresh setup "" "" || return
  fi
  chains="$(cat "$records/chains.txt" 2>/dev/null || true)"
  case "$chains" in
    '' | *[!0-9]* | 0) fail "$calibration for $location has no recorded chain count: its setup did not finish (see its setup attempt and log). Preserve this run. To try again, register and run a new calibration code; completed earlier stages in this output folder are reused." ;;
  esac
  if [ "$chains" -eq 1 ]; then
    run_phase "$location" "$calibration" resume run 1 "" || return
  else
    batch="${SHIELD_MAX_PARALLEL_CHAINS:-$chains}"
    case "$batch" in '' | *[!0-9]* | 0) fail "SHIELD_MAX_PARALLEL_CHAINS must be a positive integer" ;; esac
    mkdir -p "$records/logs" || fail "cannot create $records/logs"
    failed=0
    first=1
    while [ "$first" -le "$chains" ]; do
      last=$((first + batch - 1))
      [ "$last" -le "$chains" ] || last="$chains"
      pids=""
      chain="$first"
      while [ "$chain" -le "$last" ]; do
        chain_log="$records/logs/$(date -u +%Y%m%dT%H%M%SZ)-chain$chain.log"
        run_phase "$location" "$calibration" resume run "$chain" "$chain_log" &
        pids="$pids $!:$chain"
        printf 'SHIELD stage: %s for %s chain %s started (log: %s)\n' \
          "$calibration" "$location" "$chain" "${chain_log#"$JHEEM_ROOT_DIR"/}"
        chain=$((chain + 1))
      done
      for entry in $pids; do
        chain_exit=0
        wait "${entry%%:*}" || chain_exit=$?
        printf 'SHIELD stage: %s for %s chain %s finished (exit %s)\n' \
          "$calibration" "$location" "${entry#*:}" "$chain_exit"
        [ "$chain_exit" -eq 0 ] || failed=1
      done
      first=$((last + 1))
    done
    if [ "$failed" -ne 0 ]; then
      printf 'SHIELD stage: %s for %s has a failed chain; not assembling. Run it again to continue.\n' \
        "$calibration" "$location" >&2
      return 1
    fi
  fi
  run_phase "$location" "$calibration" resume assemble "" ""
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
