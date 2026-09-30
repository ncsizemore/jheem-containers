#!/usr/bin/env bash
# Start, check, stop, and resume SHIELD calibrations in the recorded container
# on a team server. See RUNBOOK.md.
#
#   shield-run.sh setup                                check prerequisites, load the image
#   shield-run.sh start    <location> <calibration>    begin a new calibration
#   shield-run.sh pipeline <location> <calibration>... run stages in order (runs again to continue)
#   shield-run.sh status                               show your SHIELD runs
#   shield-run.sh logs     <location> <calibration>    show the latest output
#   shield-run.sh stop     <location> <calibration>    interrupt a running calibration or pipeline
#   shield-run.sh resume   <location> <calibration>    continue from the last checkpoint
#
# Settings (normally left at their defaults):
#   SHIELD_HOME        shared image and input folder (/home/jheem-shared/shield-container)
#   SHIELD_STATE_ROOT  where calibration state and outputs go
#                      (/mnt/jheem_nas_share/tmp/shield-container/<you>)
set -euo pipefail

SHIELD_HOME="${SHIELD_HOME:-/home/jheem-shared/shield-container}"
STATE_ROOT="${SHIELD_STATE_ROOT:-/mnt/jheem_nas_share/tmp/shield-container/$(id -un)}"
IMAGE="${SHIELD_IMAGE:-docker.io/library/jheem-shield:ci}"
CENSUS_TAG="${CENSUS_TAG:-data-managers-v2026.08.26}"
SYPHILIS_TAG="${SYPHILIS_TAG:-syphilis-manager-v2026.07.27}"
SEED="${SHIELD_RANDOM_SEED:-20260916}"

say() { printf '%s\n' "$*"; }
fail() { printf 'shield-run: %s\n' "$*" >&2; exit 1; }

safe_name() { printf '%s' "$*" | tr -c 'A-Za-z0-9_.-' '-'; }
on_cifs() { case "$(stat -f -c %T "$1" 2>/dev/null)" in cifs|smb2|smb3) return 0 ;; *) return 1 ;; esac; }

# Layouts of the pinned jheem2 (<version>/<calibration>/<location>) and of the
# recorded runtime's run records.
calibration_dir() { printf '%s/mcmc_runs/shield/%s/%s' "$STATE_ROOT" "$2" "$1"; }
records_dir() { printf '%s/run_records/shield/%s/%s' "$STATE_ROOT" "$1" "$2"; }

label() { podman inspect --format "{{index .Config.Labels \"$2\"}}" "$1" 2>/dev/null; }

check_prerequisites() {
  command -v podman >/dev/null || fail "podman is not installed on this server."
  [[ "$(loginctl show-user "$(id -un)" -p Linger --value 2>/dev/null)" == yes ]] \
    || fail "lingering is off for $(id -un), so a run would stop when you log out.
Ask the server administrator to run: sudo loginctl enable-linger $(id -un)"
  [[ -f "$SHIELD_HOME/image/IMAGE.txt" ]] || fail "missing $SHIELD_HOME/image/IMAGE.txt; the administrator setup isn't done."
  [[ -d "$SHIELD_HOME/cache/data-managers" ]] || fail "missing $SHIELD_HOME/cache; the administrator setup isn't done."
  mkdir -p "$STATE_ROOT" || fail "can't create $STATE_ROOT."
  [[ -w "$STATE_ROOT" ]] || fail "$STATE_ROOT isn't writable by you."
  if on_cifs "$STATE_ROOT" && [[ "$(getsebool virt_use_samba 2>/dev/null)" != *"--> on" ]]; then
    fail "containers can't reach the NAS on this server yet.
Ask the server administrator to run: sudo setsebool -P virt_use_samba on"
  fi
}

expected_image_id() { sed -n 's/^image_id=//p' "$SHIELD_HOME/image/IMAGE.txt"; }

check_image() {
  local want have
  want="$(expected_image_id)"
  have="$(podman image inspect --format '{{.Id}}' "$IMAGE" 2>/dev/null || true)"
  [[ "sha256:${have#sha256:}" == "$want" ]]
}

cmd_setup() {
  check_prerequisites
  if check_image; then
    say "Image is loaded and matches $SHIELD_HOME/image/IMAGE.txt."
  else
    local archive="$SHIELD_HOME/image/jheem-shield-recorded.tar.gz"
    [[ -f "$archive" ]] || fail "the image isn't loaded and $archive is missing."
    say "Checking and loading the image (a few minutes, about 4 GB)..."
    (cd "$SHIELD_HOME/image" && grep ' jheem-shield-recorded.tar.gz$' IMAGE.txt | sha256sum -c --quiet -) \
      || fail "the image archive doesn't match IMAGE.txt."
    podman load -q -i "$archive" >/dev/null
    check_image || fail "the loaded image doesn't match IMAGE.txt."
    say "Image loaded."
  fi
  say "Outputs will go to: $STATE_ROOT"
  say "Setup is complete."
}

# The container (running, or else the most recent) that runs this calibration
# for this location, alone or as a pipeline stage.
find_container() {
  local location="$1" calibration="$2" name found=""
  while read -r name; do
    [[ -n "$name" && "$(label "$name" shield.location)" == "$location" ]] || continue
    [[ " $(label "$name" shield.calibrations) " == *" $calibration "* ]] || continue
    if [[ "$(podman container inspect --format '{{.State.Running}}' "$name")" == true ]]; then
      printf '%s' "$name"; return 0
    fi
    [[ -n "$found" ]] || found="$name"
  done < <(podman ps -a --filter name=^shield- --sort created --format '{{.Names}}' | tac)
  [[ -z "$found" ]] || printf '%s' "$found"
}

# Refuse to start a second writer for any of these calibrations.
check_not_running() {
  local location="$1" name calibration
  shift
  for calibration in "$@"; do
    name="$(find_container "$location" "$calibration")"
    if [[ -n "$name" && "$(podman container inspect --format '{{.State.Running}}' "$name")" == true ]]; then
      fail "$calibration for $location is already running. Check it with: shield-run.sh status"
    fi
  done
}

# Run the image detached. Arguments: container name, the calibrations it
# covers, location, run mode (empty for a pipeline), then the container command.
run_container() {
  local name="$1" calibrations="$2" location="$3" mode="$4" state_opts smoke_env=() freq_env=() mode_env=() calibration
  shift 4
  podman rm -f "$name" >/dev/null 2>&1 || true

  state_opts=""
  on_cifs "$STATE_ROOT" || state_opts=",relabel=shared"
  if [[ " $calibrations" == *" container.smoke."* ]]; then
    for calibration in $calibrations; do
      [[ "$calibration" == container.smoke.* ]] \
        || fail "don't mix test (container.smoke.*) and real calibrations in one run."
    done
    smoke_env=(--env SHIELD_ENABLE_CONTAINER_SMOKE=true)
    freq_env=(--env SHIELD_CACHE_FREQUENCY=1 --env SHIELD_UPDATE_FREQUENCY=1)
  fi
  [[ -z "$mode" ]] || mode_env=(--env "SHIELD_RUN_MODE=$mode")

  podman run -d --name "$name" \
    --label shield.location="$location" --label shield.calibrations="$calibrations" \
    --userns=keep-id --group-add keep-groups --network none \
    --user "$(id -u):$(id -g)" \
    --mount "type=bind,src=$SHIELD_HOME/cache,dst=/work/cache,readonly" \
    --mount "type=bind,src=$STATE_ROOT,dst=/work/state$state_opts" \
    --env "JHEEM_CENSUS_MANAGER_TAG=$CENSUS_TAG" \
    --env "JHEEM_SYPHILIS_MANAGER_TAG=$SYPHILIS_TAG" \
    --env "SHIELD_RANDOM_SEED=$SEED" \
    --env "SHIELD_IMAGE_ID=$(expected_image_id)" \
    --env "SHIELD_OPERATOR=$(id -un)" \
    --env "SHIELD_HOST=$(hostname -s)" \
    "${smoke_env[@]}" "${freq_env[@]}" "${mode_env[@]}" \
    "$IMAGE" "$@" >/dev/null
}

cmd_stage() {
  local mode="$1" location="$2" calibration="$3" saved
  check_prerequisites
  check_image || fail "the image isn't loaded; run: shield-run.sh setup"
  check_not_running "$location" "$calibration"
  saved="$(calibration_dir "$location" "$calibration")"
  if [[ "$mode" == fresh && -e "$saved" ]]; then
    fail "$calibration for $location already has saved results in:
  $saved
To continue it: shield-run.sh resume $location $calibration
To start over, remove that folder and $(records_dir "$location" "$calibration") first."
  fi
  if [[ "$mode" == resume && ! -s "$saved/cache/chain1_control.Rdata" ]]; then
    fail "there's nothing to resume for $calibration $location (no saved checkpoint in $saved).
To begin it: shield-run.sh start $location $calibration"
  fi

  run_container "$(safe_name "shield-$calibration-$location")" "$calibration" "$location" "$mode" \
    calibrate "$location" "$calibration"
  say "Started ($mode): $calibration for $location."
  say "  Check progress:  shield-run.sh status"
  say "  Latest output:   shield-run.sh logs $location $calibration"
  say "  Outputs:         $STATE_ROOT"
  say "It keeps running if you log out."
}

cmd_pipeline() {
  local location="$1" calibration
  shift
  check_prerequisites
  check_image || fail "the image isn't loaded; run: shield-run.sh setup"
  check_not_running "$location" "$@"
  # A stage with calibration state but no recorded start wasn't made by a
  # recorded run, and would stop the pipeline partway; refuse it up front.
  for calibration in "$@"; do
    if [[ -e "$(calibration_dir "$location" "$calibration")" && ! -f "$(records_dir "$location" "$calibration")/inputs.json" ]]; then
      fail "$calibration for $location has saved results that weren't started by this container:
  $(calibration_dir "$location" "$calibration")
Remove that folder to run this stage from the start."
    fi
  done

  run_container "$(safe_name "shield-pipeline-$1-$location")" "$*" "$location" "" \
    pipeline "$location" "$@"
  say "Started pipeline for $location: $*"
  say "Each stage starts when the previous one finishes."
  say "  Check progress:  shield-run.sh status"
  say "  Latest output:   shield-run.sh logs $location <calibration>"
  say "  To continue it after a stop or failure, run the same pipeline command again."
  say "It keeps running if you log out."
}

stage_progress() {
  local location="$1" calibration="$2" chunks
  if [[ -f "$(records_dir "$location" "$calibration")/outputs.json" ]]; then
    printf 'done'
  elif [[ -e "$(calibration_dir "$location" "$calibration")" ]]; then
    chunks="$( (find "$(calibration_dir "$location" "$calibration")/cache/chain_1" -maxdepth 1 -name 'chain1_chunk*.Rdata' 2>/dev/null || true) | wc -l | tr -d ' ')"
    printf 'checkpoints saved: %s' "$chunks"
  else
    printf 'not started'
  fi
}

cmd_status() {
  local names name location calibrations state last calibration
  names="$(podman ps -a --filter name=^shield- --sort created --format '{{.Names}}')"
  if [[ -z "$names" ]]; then say "No SHIELD runs found."; return; fi
  while read -r name; do
    location="$(label "$name" shield.location)"
    calibrations="$(label "$name" shield.calibrations)"
    state="$(podman inspect --format '{{.State.Status}} (exit {{.State.ExitCode}})' "$name")"
    [[ "$state" == running* ]] && state="running"
    last="$(podman logs --tail 1 "$name" 2>&1 | cut -c1-100)"
    if [[ "$name" == shield-pipeline-* ]]; then
      say "pipeline $location: $state"
      for calibration in $calibrations; do
        say "    $calibration: $(stage_progress "$location" "$calibration")"
      done
    else
      say "$calibrations $location: $state; $(stage_progress "$location" "$calibrations")"
    fi
    say "    last output: $last"
  done <<<"$names"
}

container_for() {
  local name
  name="$(find_container "$1" "$2")"
  [[ -n "$name" ]] || fail "no run found for $2 $1."
  printf '%s' "$name"
}

cmd_logs() { podman logs --tail 40 "$(container_for "$1" "$2")"; }

cmd_stop() {
  local name
  name="$(container_for "$1" "$2")"
  # R ignores the polite stop signal, so podman forces it after 5 seconds.
  podman stop -t 5 "$name" >/dev/null 2>&1
  if [[ "$name" == shield-pipeline-* ]]; then
    say "Stopped the pipeline for $1 ($(label "$name" shield.calibrations))."
    say "Continue it later by running the same pipeline command again."
  else
    say "Stopped $2 for $1. Continue it later with: shield-run.sh resume $1 $2"
  fi
}

case "${1:-}" in
  setup)    cmd_setup ;;
  start)    [[ $# -eq 3 ]] || fail "usage: shield-run.sh start <location> <calibration>"; cmd_stage fresh "$2" "$3" ;;
  resume)   [[ $# -eq 3 ]] || fail "usage: shield-run.sh resume <location> <calibration>"; cmd_stage resume "$2" "$3" ;;
  pipeline) [[ $# -ge 3 ]] || fail "usage: shield-run.sh pipeline <location> <calibration>..."; shift; cmd_pipeline "$@" ;;
  stop)     [[ $# -eq 3 ]] || fail "usage: shield-run.sh stop <location> <calibration>"; cmd_stop "$2" "$3" ;;
  logs)     [[ $# -eq 3 ]] || fail "usage: shield-run.sh logs <location> <calibration>"; cmd_logs "$2" "$3" ;;
  status)   cmd_status ;;
  *) sed -n '2,17p' "$0" | sed 's/^# \{0,1\}//'; exit 64 ;;
esac
