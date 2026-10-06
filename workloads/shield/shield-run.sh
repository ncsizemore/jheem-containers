#!/usr/bin/env bash
# Start, check, stop, and resume SHIELD calibrations in the recorded container
# on a team server. Operator guide: jheem_analyses/applications/SHIELD/CONTAINER-PILOT.md.
#
#   shield-run.sh setup                                check prerequisites, load the image
#   shield-run.sh start    <location> <calibration>    begin a new calibration
#   shield-run.sh pipeline <location> <calibration>... run stages in order (runs again to continue)
#   shield-run.sh batch <location,location,...> <calibration>...
#                                                      run that pipeline for each location, a few at a time
#   shield-run.sh stop-batch <batch-id>                stop a batch and its running locations
#   shield-run.sh status                               show your SHIELD runs
#   shield-run.sh where                                where outputs go, and how analyses read them
#   shield-run.sh logs     <location> <calibration>    show the latest output
#   shield-run.sh stop     <location> <calibration>    interrupt a running calibration or pipeline
#   shield-run.sh resume   <location> <calibration>    continue from the last checkpoint
#
# Settings (normally left at their defaults):
#   SHIELD_HOME        shared image and input folder (the installed wrapper directory)
#   SHIELD_STATE_ROOT  where calibration state and outputs go
#                      (/mnt/jheem_nas_share/tmp/shield-container/<you>)
#   SHIELD_RANDOM_SEED random seed (0, as the team's launcher uses)
#   SHIELD_JHEEM2_DIR  jheem2 checkout for new runs (default: next to jheem_analyses)
#   SHIELD_ENGINE      set to "image" to use the runtime image's built-in jheem2
#   SHIELD_MAX_PARALLEL_CHAINS  chains of one stage to run at once (default: all)
#   SHIELD_MAX_CITIES  locations of a batch to run at once (default: 5)
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
# this state root. A pipeline binds all requested stages to one selection: the
# analysis code and, unless SHIELD_ENGINE=image, the jheem2 checkout.
select_source() {
  local mode="$1" details have engine_source resume_args=()
  shift
  [[ "$mode" != resume ]] || resume_args=(--resume)
  engine_source="${SHIELD_JHEEM2_DIR:-}"
  [[ "${SHIELD_ENGINE:-}" != image ]] || engine_source=image
  details="$(python3 "$SCRIPT_DIR/source_snapshot.py" \
    --root "$STATE_ROOT" --source "${SHIELD_SOURCE_DIR:-$PWD}" \
    --image "$(expected_image_id)" --census "$CENSUS_TAG" \
    --syphilis "$SYPHILIS_TAG" --seed "$SEED" --engine-source "$engine_source" \
    ${resume_args[@]+"${resume_args[@]}"} "$@")" || exit 1
  IFS=$'\t' read -r SOURCE_TREE SOURCE_REF RUN_IMAGE CENSUS_TAG SYPHILIS_TAG SEED SOURCE_DIGEST \
    ENGINE_KEY ENGINE_TREE ENGINE_REF <<< "$details"
  have="$(podman image inspect --format '{{.Id}}' "$RUN_IMAGE" 2>/dev/null || true)"
  [[ "sha256:${have#sha256:}" == "$RUN_IMAGE" ]] \
    || fail "the run's recorded image $RUN_IMAGE is not loaded; restore that exact image before continuing."
  say "Using saved analysis code ${SOURCE_REF:0:8} (all requested stages and locations)."
  if [[ "$ENGINE_KEY" == image ]]; then
    ENGINE_LIBRARY=""
    say "Using the runtime image's built-in jheem2."
  else
    ENGINE_LIBRARY="$(python3 "$SCRIPT_DIR/engine_build.py" --root "$STATE_ROOT" \
      --engine "$ENGINE_KEY" --image "$RUN_IMAGE" --script-dir "$SCRIPT_DIR")" || exit 1
    say "Using saved jheem2 ${ENGINE_REF:0:8}, built for this runtime."
  fi
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

# Container settings for these calibrations and run mode (empty for a
# pipeline), shared by the compatibility check and every launch: sets RUNTIME_ARGS.
prepare_runtime() {
  local calibrations="$1" mode="$2" state_opts source_opts smoke_env=() freq_env=() mode_env=() calibration
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
  local parallel_env=()
  [[ -z "${SHIELD_MAX_PARALLEL_CHAINS:-}" ]] \
    || parallel_env=(--env "SHIELD_MAX_PARALLEL_CHAINS=$SHIELD_MAX_PARALLEL_CHAINS")
  # A captured engine replaces the image's jheem2 in every R process of the run.
  local engine_args=()
  if [[ -n "$ENGINE_LIBRARY" ]]; then
    engine_args=(
      --mount "type=bind,src=$ENGINE_TREE,dst=/opt/run-engine/jheem2,readonly$source_opts"
      --mount "type=bind,src=$ENGINE_LIBRARY,dst=/opt/run-engine/library,readonly$source_opts"
      --mount "type=bind,src=$SCRIPT_DIR/engine-profile.R,dst=/opt/shield/engine-profile.R,readonly"
      --env JHEEM2_PATH=/opt/run-engine/jheem2
      --env "JHEEM2_REF=$ENGINE_REF"
      --env SHIELD_ENGINE_LIBRARY=/opt/run-engine/library
      --env R_PROFILE_USER=/opt/shield/engine-profile.R
    )
  fi

  RUNTIME_ARGS=(
    --userns=keep-id --group-add keep-groups --network none \
    --user "$(id -u):$(id -g)" \
    --mount "type=bind,src=$SHIELD_HOME/cache,dst=/work/cache,readonly" \
    --mount "type=bind,src=$STATE_ROOT,dst=/work/state$state_opts" \
    --mount "type=bind,src=$STATE_ROOT/run_sources,dst=/work/state/run_sources,readonly$source_opts" \
    --mount "type=bind,src=$SOURCE_TREE,dst=/opt/run-source/jheem_analyses,readonly$source_opts" \
    --mount "type=bind,src=$SCRIPT_DIR/check_source_compatibility.R,dst=/opt/shield/check_source_compatibility.R,readonly" \
    --mount "type=bind,src=$SCRIPT_DIR/container-entrypoint.sh,dst=/opt/shield/container-entrypoint.sh,readonly" \
    --env JHEEM_ANALYSES_PATH=/opt/run-source/jheem_analyses \
    --env "JHEEM_ANALYSES_REF=$SOURCE_REF" \
    --env "JHEEM_CENSUS_MANAGER_TAG=$CENSUS_TAG" \
    --env "JHEEM_SYPHILIS_MANAGER_TAG=$SYPHILIS_TAG" \
    --env "SHIELD_RANDOM_SEED=$SEED" \
    --env "SHIELD_IMAGE_ID=$RUN_IMAGE" \
    --env "SHIELD_OPERATOR=$(id -un)" \
    --env "SHIELD_HOST=$(hostname -s)" \
    ${smoke_env[@]+"${smoke_env[@]}"} ${freq_env[@]+"${freq_env[@]}"} ${mode_env[@]+"${mode_env[@]}"}
    ${engine_args[@]+"${engine_args[@]}"} ${parallel_env[@]+"${parallel_env[@]}"}
  )
}

# Load the selected specification and calibration definitions read-only before
# any sampling; one check covers every location of these calibrations.
check_compatibility() {
  say "Checking the selected code, inputs, and calibration definitions..."
  podman run --rm "${RUNTIME_ARGS[@]}" "$RUN_IMAGE" shell -c \
    'Rscript /opt/shield/preflight.R && Rscript /opt/shield/check_source_compatibility.R "$@"' \
    shield-source-check $1 || fail "source compatibility check failed; no calibration was launched. Preserve the saved selection and logs."
}

# Start one detached container. Arguments: name prefix, location, calibrations,
# batch ID (or empty), then the container command. Prints the container name.
launch_detached() {
  local name="$1" location="$2" calibrations="$3" batch="$4" batch_label=()
  shift 4
  [[ -z "$batch" ]] || batch_label=(--label "shield.batch=$batch")
  # Do not remove old container diagnostics or race another launcher by force.
  # Podman atomically reserves a unique attempt name; the running check is
  # still same-account only, not a general shared-writer lock.
  name="$name-$(date -u +%Y%m%dT%H%M%S)-$$"
  podman run -d --name "$name" \
    --label shield.location="$location" --label shield.calibrations="$calibrations" \
    --label shield.state-root="$STATE_ROOT" ${batch_label[@]+"${batch_label[@]}"} \
    "${RUNTIME_ARGS[@]}" "$RUN_IMAGE" "$@" >/dev/null || return 1
  printf '%s' "$name"
}

# Check, then launch. Arguments: name prefix, calibrations, location, run mode
# (empty for a pipeline), then the container command.
run_container() {
  local name="$1" calibrations="$2" location="$3" mode="$4"
  shift 4
  prepare_runtime "$calibrations" "$mode"
  check_compatibility "$calibrations"
  launch_detached "$name" "$location" "$calibrations" "" "$@" >/dev/null || fail "could not start the container."
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
Preserve this run for diagnosis; do not delete saved state or records. For a new
attempt, register and run a new calibration code: completed earlier stages in this
output folder are reused. (A separate SHIELD_STATE_ROOT also works, without them.)"
  fi
  if [[ "$mode" == resume && ! -s "$saved/cache/chain1_control.Rdata" ]]; then
    fail "there's nothing to resume for $calibration $location (no saved checkpoint in $saved).
If setup already started, preserve its state and records for diagnosis. For a new
attempt, register and run a new calibration code: completed earlier stages in this
output folder are reused. Use start only for a run that has not already been started."
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

# Calibration state that no recorded run started would stop a pipeline partway.
# Prints the first such calibration for this location.
unrecorded_state() {
  local location="$1" calibration
  shift
  for calibration in "$@"; do
    if [[ -e "$(calibration_dir "$location" "$calibration")" && ! -f "$(records_dir "$location" "$calibration")/inputs.json" ]]; then
      printf '%s' "$calibration"
      return 0
    fi
  done
  return 1
}

# Prints a running container that covers any of these calibrations here.
running_container() {
  local location="$1" calibration name
  shift
  for calibration in "$@"; do
    name="$(find_container "$location" "$calibration")"
    if [[ -n "$name" && "$(podman container inspect --format '{{.State.Running}}' "$name")" == true ]]; then
      printf '%s' "$name"
      return 0
    fi
  done
  return 1
}

batch_dir() { printf '%s/run_batches/%s' "$STATE_ROOT" "$1"; }
batch_worker_alive() {
  local pid
  pid="$(cat "$(batch_dir "$1")/worker.pid" 2>/dev/null || true)"
  [[ -n "$pid" ]] && ps -p "$pid" -o command= 2>/dev/null | grep -q "_batch-worker $1"
}

# A batch runs one pipeline container per location, at most SHIELD_MAX_CITIES at
# a time. Selection, engine build, and the compatibility check happen once, here;
# a background scheduler then starts locations as earlier ones finish. Like the
# team's nohup launchers, it continues after logout.
cmd_batch() {
  local list="$1" city cities=() code max="${SHIELD_MAX_CITIES:-5}" id dir launcher=()
  shift
  [[ "$max" =~ ^[1-9][0-9]*$ ]] || fail "SHIELD_MAX_CITIES must be a positive integer."
  IFS=',' read -r -a cities <<< "$list"
  (( ${#cities[@]} > 0 )) || fail "no locations given."
  for city in "${cities[@]}"; do
    [[ "$city" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || fail "invalid location: '$city'"
  done
  [[ -z "$(printf '%s\n' "${cities[@]}" | sort | uniq -d)" ]] || fail "a location is listed twice."
  for code in "$@"; do
    [[ "$code" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || fail "invalid calibration code: '$code'"
  done
  check_prerequisites
  for city in "${cities[@]}"; do
    if code="$(unrecorded_state "$city" "$@")"; then
      fail "$code for $city has saved results that weren't started by this container:
  $(calibration_dir "$city" "$code")
Leave that location out of the batch, or use a separate SHIELD_STATE_ROOT; do not delete saved state."
    fi
  done

  select_source pipeline "$@"
  prepare_runtime "$*" ""
  check_compatibility "$*"

  id="$(date -u +%Y%m%dT%H%M%SZ)-$$"
  dir="$(batch_dir "$id")"
  mkdir -p "$dir" || fail "can't create $dir."
  printf '%s\n' "${cities[@]}" > "$dir/locations.txt"
  printf '%s\n' "$@" > "$dir/calibrations.txt"
  printf '%s\n' "$max" > "$dir/max_cities.txt"
  ! command -v setsid >/dev/null || launcher=(setsid)
  SHIELD_HOME="$SHIELD_HOME" SHIELD_STATE_ROOT="$STATE_ROOT" SHIELD_SOURCE_DIR="${SHIELD_SOURCE_DIR:-$PWD}" \
    nohup ${launcher[@]+"${launcher[@]}"} bash "$SCRIPT_DIR/shield-run.sh" _batch-worker "$id" \
    </dev/null >>"$dir/batch.log" 2>&1 &
  say "Started batch $id: ${#cities[@]} locations, at most $max at a time."
  say "  Stages:          $*"
  say "  Check progress:  shield-run.sh status"
  say "  Batch log:       $dir/batch.log"
  say "  Stop it:         shield-run.sh stop-batch $id"
  say "Running the same batch command again continues it. It keeps running if you log out."
}

batch_worker() {
  local id="$1" dir line city name state code i running waiting max poll
  local locations=() codes=() states=()
  dir="$(batch_dir "$id")"
  [[ -f "$dir/locations.txt" ]] || fail "no batch $id in $STATE_ROOT."
  printf '%s\n' "$$" > "$dir/worker.pid"
  while IFS= read -r line; do [[ -z "$line" ]] || locations+=("$line"); done < "$dir/locations.txt"
  while IFS= read -r line; do [[ -z "$line" ]] || codes+=("$line"); done < "$dir/calibrations.txt"
  max="$(cat "$dir/max_cities.txt")"
  poll="${SHIELD_BATCH_POLL_SECONDS:-60}"
  note() { printf '[%s] %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*"; }
  note "batch $id: ${#locations[@]} locations, at most $max at a time: ${codes[*]}"
  select_source pipeline "${codes[@]}"
  prepare_runtime "${codes[*]}" ""
  for city in "${locations[@]}"; do states+=(waiting); done
  while :; do
    running=0
    for i in "${!locations[@]}"; do
      state="${states[$i]}"
      [[ "$state" == running\ * ]] || continue
      name="${state#running }"
      if [[ "$(podman container inspect --format '{{.State.Running}}' "$name" 2>/dev/null)" == true ]]; then
        running=$((running + 1))
      else
        code="$(podman container inspect --format '{{.State.ExitCode}}' "$name" 2>/dev/null || echo unknown)"
        states[$i]="finished (exit $code)"
        note "${locations[$i]} finished (exit $code)"
      fi
    done
    for i in "${!locations[@]}"; do
      (( running < max )) || break
      [[ "${states[$i]}" == waiting ]] || continue
      city="${locations[$i]}"
      if name="$(running_container "$city" "${codes[@]}")"; then
        states[$i]="skipped (already running: $name)"
        note "$city skipped: already running in $name"
      elif code="$(unrecorded_state "$city" "${codes[@]}")"; then
        states[$i]="skipped ($code has state not started by this container)"
        note "$city skipped: $code has state not started by this container"
      elif name="$(launch_detached "$(safe_name "shield-pipeline-${codes[0]}-$city")" "$city" \
          "${codes[*]}" "$id" pipeline "$city" "${codes[@]}")"; then
        states[$i]="running $name"
        running=$((running + 1))
        note "$city started ($name)"
      else
        states[$i]="skipped (could not start)"
        note "$city could not start"
      fi
    done
    for i in "${!locations[@]}"; do printf '%s %s\n' "${locations[$i]}" "${states[$i]}"; done \
      > "$dir/status.txt.tmp" && mv "$dir/status.txt.tmp" "$dir/status.txt"
    waiting=0
    for state in "${states[@]}"; do [[ "$state" != waiting ]] || waiting=$((waiting + 1)); done
    (( running > 0 || waiting > 0 )) || break
    sleep "$poll"
  done
  note "batch $id finished"
}

batch_summary() {
  local id="$1" status counts
  status="$(batch_dir "$id")/status.txt"
  counts="$(awk '{ if ($2 == "finished" && $0 !~ /\(exit 0\)$/) print "failed"; else print $2 }' "$status" 2>/dev/null \
    | sort | uniq -c | awk '{printf "%s%s %s", (NR>1 ? ", " : ""), $1, $2}')"
  if batch_worker_alive "$id"; then
    say "batch $id: scheduling (${counts:-starting})"
  else
    say "batch $id: done (${counts:-no locations started})"
  fi
}

cmd_stop_batch() {
  local id="$1" name pid
  [[ -d "$(batch_dir "$id")" ]] || fail "no batch $id in $STATE_ROOT."
  if batch_worker_alive "$id"; then
    pid="$(cat "$(batch_dir "$id")/worker.pid")"
    kill "$pid" 2>/dev/null || true
  fi
  for name in $(podman ps --filter "label=shield.batch=$id" --format '{{.Names}}'); do
    # R ignores the polite stop signal, so podman forces it after 5 seconds.
    podman stop -t 5 "$name" >/dev/null 2>&1 || true
    say "Stopped $name"
  done
  say "Stopped batch $id. Run the same batch command again to continue it."
}

chunk_count() {
  ( (find "$(calibration_dir "$1" "$2")/cache/chain_$3" -maxdepth 1 -name "chain$3_chunk*.Rdata" 2>/dev/null || true) | wc -l | tr -d ' ')
}

stage_progress() {
  local location="$1" calibration="$2" chains chain counts=()
  if [[ -f "$(records_dir "$location" "$calibration")/outputs.json" ]]; then
    printf 'outputs recorded (not rechecked)'
  elif [[ -e "$(calibration_dir "$location" "$calibration")" ]]; then
    chains="$(cat "$(records_dir "$location" "$calibration")/chains.txt" 2>/dev/null || echo 1)"
    [[ "$chains" =~ ^[1-9][0-9]*$ ]] || chains=1
    if (( chains == 1 )); then
      printf 'checkpoints saved: %s' "$(chunk_count "$location" "$calibration" 1)"
    else
      for (( chain = 1; chain <= chains; chain++ )); do
        counts+=("chain $chain: $(chunk_count "$location" "$calibration" "$chain")")
      done
      printf 'checkpoints saved (%s)' "$(IFS=,; echo "${counts[*]}" | sed 's/,/, /g')"
    fi
  else
    printf 'not started'
  fi
}

cmd_status() {
  local names name location calibrations state last calibration root batch
  if [[ -d "$STATE_ROOT/run_batches" ]]; then
    for batch in $(ls -1 "$STATE_ROOT/run_batches" | tail -5); do batch_summary "$batch"; done
  fi
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

# The team's analysis scripts find results through ROOT.DIR in
# commoncode/file_paths.R, which JHEEM_ROOT_DIR overrides. Pointing it at this
# folder lets those scripts read container results unchanged. The NAS share is
# /mnt/jheem_nas_share on the servers, /Volumes/jheem$ on a Mac, and Q: on the
# desktop, as in file_paths.R.
cmd_where() {
  local relative
  say "Your container results (calibration state, summaries, simulation sets, run records):"
  say "  $STATE_ROOT"
  [[ "$STATE_ROOT" == /mnt/jheem_nas_share/* ]] || return 0
  relative="${STATE_ROOT#/mnt/jheem_nas_share/}"
  say ""
  say "To read them with your usual SHIELD analysis scripts, set JHEEM_ROOT_DIR at the top"
  say "of the script, before it sources the SHIELD code:"
  say "  on a server:  Sys.setenv(JHEEM_ROOT_DIR = \"$STATE_ROOT\")"
  say "  on a Mac:     Sys.setenv(JHEEM_ROOT_DIR = \"/Volumes/jheem\$/$relative\")"
  say "  on Windows:   Sys.setenv(JHEEM_ROOT_DIR = \"Q:/$relative\")"
  say "In a session that already sourced it, use set.jheem.root.directory() with the same path."
  say "Figures and tables the scripts write then also go under this folder. Remove the line"
  say "(or Sys.unsetenv(\"JHEEM_ROOT_DIR\")) to go back to the usual results."
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
  batch)    [[ $# -ge 3 ]] || fail "usage: shield-run.sh batch <location,location,...> <calibration>..."; shift; cmd_batch "$@" ;;
  stop-batch) [[ $# -eq 2 ]] || fail "usage: shield-run.sh stop-batch <batch-id>"; cmd_stop_batch "$2" ;;
  _batch-worker) [[ $# -eq 2 ]] || fail "usage: shield-run.sh _batch-worker <batch-id>"; batch_worker "$2" ;;
  status)   cmd_status ;;
  where)    cmd_where ;;
  *) sed -n '2,25p' "$0" | sed 's/^# \{0,1\}//'; exit 64 ;;
esac
