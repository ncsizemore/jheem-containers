#!/usr/bin/env bash
# Start, check, stop, and resume SHIELD calibrations in the recorded container
# on a team server. Operator guide: jheem_analyses/applications/SHIELD/CONTAINER-PILOT.md.
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
#   SHIELD_HOME        shared image and input folder (the installed wrapper directory)
#   SHIELD_STATE_ROOT  where calibration state and outputs go
#                      (/mnt/jheem_nas_share/tmp/shield-container/<you>)
#   SHIELD_RANDOM_SEED random seed (0, as the team's launcher uses)
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
SHIELD_HOME="${SHIELD_HOME:-$SCRIPT_DIR}"
if [[ -e "$SHIELD_HOME/installation.json" || -L "$SHIELD_HOME/installation.json" ]]; then
  profile="$(python3 "$SCRIPT_DIR/installation_profile.py" show "$SHIELD_HOME")" || exit 1
  IFS=$'\t' read -r profile_image state_namespace profile_census profile_syphilis profile_seed <<< "$profile"
  for selection in SHIELD_IMAGE CENSUS_TAG SYPHILIS_TAG; do
    case "$selection" in
      SHIELD_IMAGE) wanted="$profile_image" ;;
      CENSUS_TAG) wanted="$profile_census" ;;
      SYPHILIS_TAG) wanted="$profile_syphilis" ;;
    esac
    [[ -z "${!selection:-}" || "${!selection}" == "$wanted" ]] || {
      echo "shield-run: $selection differs from this installation's verified profile; use a separate prepared installation for different inputs/runtime." >&2
      exit 1
    }
  done
  IMAGE="$profile_image"
  CENSUS_TAG="$profile_census"
  SYPHILIS_TAG="$profile_syphilis"
  SEED="${SHIELD_RANDOM_SEED:-$profile_seed}"
else
  # Preserve the original pilot's defaults, but never apply them to a new export.
  if [[ -f "$SHIELD_HOME/image/IMAGE.txt" ]] && grep -q '^input_profile=' "$SHIELD_HOME/image/IMAGE.txt"; then
    echo 'shield-run: this image needs a prepared installation.json; no calibration was launched.' >&2
    exit 1
  fi
  state_namespace=shield-container
  IMAGE="${SHIELD_IMAGE:-docker.io/library/jheem-shield:ci}"
  CENSUS_TAG="${CENSUS_TAG:-data-managers-v2026.08.26}"
  SYPHILIS_TAG="${SYPHILIS_TAG:-syphilis-manager-v2026.07.27}"
  SEED="${SHIELD_RANDOM_SEED:-0}"
fi
STATE_ROOT="${SHIELD_STATE_ROOT:-/mnt/jheem_nas_share/tmp/$state_namespace/$(id -un)}"
# The team's launcher runs set.seed(00000); use the same seed by default.
LAUNCH_LOCKS=()

release_launch_locks() {
  local lock
  for lock in ${LAUNCH_LOCKS[@]+"${LAUNCH_LOCKS[@]}"}; do rmdir -- "$lock"; done
}

lock_launch() {
  local location="$1" code lock
  shift
  [[ "$location" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || fail "invalid location"
  for code in "$@"; do
    [[ "$code" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || fail "invalid calibration code"
  done
  mkdir -p "$STATE_ROOT/run_locks"
  trap release_launch_locks EXIT
  for code in "$@"; do
    lock="$STATE_ROOT/run_locks/$location--$code"
    mkdir -- "$lock" 2>/dev/null || fail "a launch is already in progress for $location $code; inspect an interrupted launch before retrying."
    LAUNCH_LOCKS+=("$lock")
  done
}

# Source selections are shared by all locations of a calibration code within
# this state root. A pipeline binds all requested stages to one selection.
select_source() {
  local mode="$1" details have resume_args=()
  shift
  [[ "$mode" != resume ]] || resume_args=(--resume)
  details="$(python3 "$SCRIPT_DIR/source_snapshot.py" \
    --root "$STATE_ROOT" --source "${SHIELD_SOURCE_DIR:-$PWD}" \
    --image "$(expected_image_id)" --census "$CENSUS_TAG" \
    --syphilis "$SYPHILIS_TAG" --seed "$SEED" ${resume_args[@]+"${resume_args[@]}"} "$@")" || exit 1
  IFS=$'\t' read -r SOURCE_TREE SOURCE_REF RUN_IMAGE CENSUS_TAG SYPHILIS_TAG SEED SOURCE_DIGEST <<< "$details"
  have="$(podman image inspect --format '{{.Id}}' "$RUN_IMAGE" 2>/dev/null || true)"
  [[ "sha256:${have#sha256:}" == "$RUN_IMAGE" ]] \
    || fail "the run's recorded image $RUN_IMAGE is not loaded; restore that exact image before continuing."
  say "Using saved analysis code ${SOURCE_REF:0:8} (all requested stages and locations)."
}

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
  command -v python3 >/dev/null || fail "python3 is required for source snapshots."
  command -v podman >/dev/null || fail "podman is not installed on this server."
  [[ "$(loginctl show-user "$(id -un)" -p Linger --value 2>/dev/null)" == yes ]] \
    || fail "lingering is off for $(id -un), so a run would stop when you log out.
Ask the server administrator to run: sudo loginctl enable-linger $(id -un)"
  [[ -f "$SHIELD_HOME/image/IMAGE.txt" ]] || fail "missing $SHIELD_HOME/image/IMAGE.txt; the administrator setup isn't done."
  [[ -d "$SHIELD_HOME/cache/data-managers" ]] || fail "missing $SHIELD_HOME/cache; the administrator setup isn't done."
  [[ "$STATE_ROOT" == /* ]] || fail "SHIELD_STATE_ROOT must be an absolute path."
  if [[ "$STATE_ROOT" == /mnt/jheem_nas_share/* ]]; then
    [[ "$(findmnt -n -o FSTYPE -T /mnt/jheem_nas_share 2>/dev/null)" == cifs ]] \
      || fail "the NAS is not mounted; no pilot state was created."
  fi
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
  if [[ -f "$SHIELD_HOME/installation.json" ]]; then
    python3 "$SCRIPT_DIR/installation_profile.py" verify "$SHIELD_HOME" >/dev/null || exit 1
  fi
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
  say "Inputs: $CENSUS_TAG / $SYPHILIS_TAG; seed: $SEED"
  say "Outputs will go to: $STATE_ROOT"
  say "Setup is complete."
}

# The container (running, or else the most recent) that runs this calibration
# for this location, alone or as a pipeline stage.
find_container() {
  local location="$1" calibration="$2" name root found=""
  while read -r name; do
    [[ -n "$name" && "$(label "$name" shield.location)" == "$location" ]] || continue
    root="$(label "$name" shield.state-root)"
    [[ -z "$root" || "$root" == "$STATE_ROOT" ]] || continue
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
  local name="$1" calibrations="$2" location="$3" mode="$4" state_opts source_opts smoke_env=() freq_env=() mode_env=() calibration
  shift 4
  state_opts=""
  on_cifs "$STATE_ROOT" || state_opts=",relabel=shared"
  source_opts=""
  on_cifs "$SOURCE_TREE" || source_opts=",relabel=shared"
  if [[ " $calibrations" == *" container.smoke."* ]]; then
    for calibration in $calibrations; do
      [[ "$calibration" == container.smoke.* ]] \
        || fail "don't mix test (container.smoke.*) and real calibrations in one run."
    done
    smoke_env=(--env SHIELD_ENABLE_CONTAINER_SMOKE=true)
    freq_env=(--env SHIELD_CACHE_FREQUENCY=1 --env SHIELD_UPDATE_FREQUENCY=1)
  fi
  [[ -z "$mode" ]] || mode_env=(--env "SHIELD_RUN_MODE=$mode")

  local runtime_args=(
    --userns=keep-id --group-add keep-groups --network none \
    --user "$(id -u):$(id -g)" \
    --mount "type=bind,src=$SHIELD_HOME/cache,dst=/work/cache,readonly" \
    --mount "type=bind,src=$STATE_ROOT,dst=/work/state$state_opts" \
    --mount "type=bind,src=$STATE_ROOT/run_sources,dst=/work/state/run_sources,readonly$source_opts" \
    --mount "type=bind,src=$SOURCE_TREE,dst=/opt/run-source/jheem_analyses,readonly$source_opts" \
    --mount "type=bind,src=$SCRIPT_DIR/check_source_compatibility.R,dst=/opt/shield/check_source_compatibility.R,readonly" \
    --env JHEEM_ANALYSES_PATH=/opt/run-source/jheem_analyses \
    --env "JHEEM_ANALYSES_REF=$SOURCE_REF" \
    --env "JHEEM_CENSUS_MANAGER_TAG=$CENSUS_TAG" \
    --env "JHEEM_SYPHILIS_MANAGER_TAG=$SYPHILIS_TAG" \
    --env "SHIELD_RANDOM_SEED=$SEED" \
    --env "SHIELD_IMAGE_ID=$RUN_IMAGE" \
    --env "SHIELD_OPERATOR=$(id -un)" \
    --env "SHIELD_HOST=$(hostname -s)" \
    ${smoke_env[@]+"${smoke_env[@]}"} ${freq_env[@]+"${freq_env[@]}"} ${mode_env[@]+"${mode_env[@]}"}
  )
  say "Checking the selected code, inputs, and calibration definitions..."
  podman run --rm "${runtime_args[@]}" "$RUN_IMAGE" shell -c \
    'Rscript /opt/shield/preflight.R && Rscript /opt/shield/check_source_compatibility.R "$@"' \
    shield-source-check $calibrations || fail "source compatibility check failed; no calibration was launched. Preserve the saved selection and logs."
  # Do not remove old container diagnostics or race another launcher by force.
  # Podman atomically reserves a unique attempt name; the running check above
  # is still same-account only, not a general shared-writer lock.
  name="$name-$(date -u +%Y%m%dT%H%M%S)-$$"
  podman run -d --name "$name" \
    --label shield.location="$location" --label shield.calibrations="$calibrations" \
    --label shield.state-root="$STATE_ROOT" \
    "${runtime_args[@]}" "$RUN_IMAGE" "$@" >/dev/null
}

cmd_stage() {
  local mode="$1" location="$2" calibration="$3" saved
  check_prerequisites
  lock_launch "$location" "$calibration"
  check_not_running "$location" "$calibration"
  saved="$(calibration_dir "$location" "$calibration")"
  if [[ "$mode" == fresh && ( -e "$saved" || -e "$(records_dir "$location" "$calibration")" ) ]]; then
    fail "$calibration for $location already has saved state or run records in:
  $saved
  $(records_dir "$location" "$calibration")
If a checkpoint was saved, continue with: shield-run.sh resume $location $calibration
Preserve this run for diagnosis. For a deliberate new attempt, ask the administrator
to choose a separate SHIELD_STATE_ROOT; do not delete saved state or records."
  fi
  if [[ "$mode" == resume && ! -s "$saved/cache/chain1_control.Rdata" ]]; then
    fail "there's nothing to resume for $calibration $location (no saved checkpoint in $saved).
If setup already started, preserve its state and records for diagnosis. Ask the
administrator for a separate SHIELD_STATE_ROOT for a deliberate new attempt.
Use start only for a run that has not already been started."
  fi

  select_source "$mode" "$calibration"
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
  lock_launch "$location" "$@"
  check_not_running "$location" "$@"
  # A stage with calibration state but no recorded start wasn't made by a
  # recorded run, and would stop the pipeline partway; refuse it up front.
  for calibration in "$@"; do
    if [[ -e "$(calibration_dir "$location" "$calibration")" && ! -f "$(records_dir "$location" "$calibration")/inputs.json" ]]; then
      fail "$calibration for $location has saved results that weren't started by this container:
  $(calibration_dir "$location" "$calibration")
Preserve this run for diagnosis. Ask the administrator to choose a separate
SHIELD_STATE_ROOT for a deliberate new attempt; do not delete saved state."
    fi
  done

  select_source pipeline "$@"
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
    printf 'outputs recorded (not rechecked)'
  elif [[ -e "$(calibration_dir "$location" "$calibration")" ]]; then
    chunks="$( (find "$(calibration_dir "$location" "$calibration")/cache/chain_1" -maxdepth 1 -name 'chain1_chunk*.Rdata' 2>/dev/null || true) | wc -l | tr -d ' ')"
    printf 'checkpoints saved: %s' "$chunks"
  else
    printf 'not started'
  fi
}

cmd_status() {
  local names name location calibrations state last calibration root
  names="$(podman ps -a --filter name=^shield- --sort created --format '{{.Names}}')"
  if [[ -z "$names" ]]; then say "No SHIELD runs found."; return; fi
  while read -r name; do
    root="$(label "$name" shield.state-root)"
    [[ -z "$root" || "$root" == "$STATE_ROOT" ]] || continue
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
