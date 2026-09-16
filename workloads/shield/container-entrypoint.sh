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

command_name="${1:-preflight}"

case "$command_name" in
  shell)
    shift
    exec "${SHELL:-/bin/bash}" "$@"
    ;;
  preflight)
    exec Rscript /opt/shield/preflight.R
    ;;
  engine-test)
    Rscript /opt/shield/preflight.R
    exec Rscript "${JHEEM_ANALYSES_PATH}/applications/SHIELD/shield_engine_test.R"
    ;;
  calibrate)
    [ "$#" -eq 3 ] || fail "usage: calibrate <location> <calibration-code>"
    Rscript /opt/shield/preflight.R
    exec Rscript \
      "${JHEEM_ANALYSES_PATH}/applications/SHIELD/shield_calib_setup_and_run.R" \
      "$2" "$3"
    ;;
  calibration-stage)
    [ "$#" -ge 4 ] && [ "$#" -le 5 ] \
      || fail "usage: calibration-stage <location> <calibration-code> <setup|run|assemble|all> [chain]"
    Rscript /opt/shield/preflight.R
    shift
    exec Rscript \
      "${JHEEM_ANALYSES_PATH}/applications/SHIELD/shield_calib_setup_and_run_modular.R" \
      "$@"
    ;;
  *)
    fail "unknown command '$command_name' (expected preflight, engine-test, calibrate, calibration-stage, or shell)"
    ;;
esac
