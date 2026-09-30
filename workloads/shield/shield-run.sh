#!/usr/bin/env bash
# Start, check, stop, and resume SHIELD calibrations in the recorded container
# on a team server. See RUNBOOK.md.
#
#   shield-run.sh setup                          check prerequisites, load the image
#   shield-run.sh start  <location> <calibration>   begin a new calibration
#   shield-run.sh status                         show your SHIELD containers
#   shield-run.sh logs   <location> <calibration>   show the latest output
#   shield-run.sh stop   <location> <calibration>   interrupt a running calibration
#   shield-run.sh resume <location> <calibration>   continue from the last checkpoint
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

container_name() { printf 'shield-%s-%s' "$2" "$1" | tr -c 'A-Za-z0-9_.-' '-'; }
on_cifs() { case "$(stat -f -c %T "$1" 2>/dev/null)" in cifs|smb2|smb3) return 0 ;; *) return 1 ;; esac; }

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

run_container() {
  local mode="$1" location="$2" calibration="$3" name state_opts smoke_env=() freq_env=()
  check_prerequisites
  check_image || fail "the image isn't loaded; run: shield-run.sh setup"
  name="$(container_name "$location" "$calibration")"
  if [[ "$(podman container inspect --format '{{.State.Running}}' "$name" 2>/dev/null)" == true ]]; then
    fail "$calibration for $location is already running. Check it with: shield-run.sh status"
  fi
  # Calibration layout of the pinned jheem2: <version>/<calibration>/<location>.
  local saved="$STATE_ROOT/mcmc_runs/shield/$calibration/$location"
  if [[ "$mode" == fresh && -e "$saved" ]]; then
    fail "$calibration for $location already has saved results in:
  $saved
To continue it: shield-run.sh resume $location $calibration
To start over, remove that folder first."
  fi
  if [[ "$mode" == resume && ! -s "$saved/cache/chain1_control.Rdata" ]]; then
    fail "there's nothing to resume for $calibration $location (no saved checkpoint in $saved).
To begin it: shield-run.sh start $location $calibration"
  fi
  podman rm -f "$name" >/dev/null 2>&1 || true

  state_opts=""
  on_cifs "$STATE_ROOT" || state_opts=",relabel=shared"
  if [[ "$calibration" == container.smoke.* ]]; then
    smoke_env=(--env SHIELD_ENABLE_CONTAINER_SMOKE=true)
    freq_env=(--env SHIELD_CACHE_FREQUENCY=1 --env SHIELD_UPDATE_FREQUENCY=1)
  fi

  podman run -d --name "$name" \
    --label shield.location="$location" --label shield.calibration="$calibration" \
    --userns=keep-id --group-add keep-groups --network none \
    --user "$(id -u):$(id -g)" \
    --mount "type=bind,src=$SHIELD_HOME/cache,dst=/work/cache,readonly" \
    --mount "type=bind,src=$STATE_ROOT,dst=/work/state$state_opts" \
    --env "JHEEM_CENSUS_MANAGER_TAG=$CENSUS_TAG" \
    --env "JHEEM_SYPHILIS_MANAGER_TAG=$SYPHILIS_TAG" \
    --env "SHIELD_RANDOM_SEED=$SEED" \
    --env "SHIELD_RUN_MODE=$mode" \
    "${smoke_env[@]}" "${freq_env[@]}" \
    "$IMAGE" calibrate "$location" "$calibration" >/dev/null

  say "Started ($mode): $calibration for $location."
  say "  Check progress:  shield-run.sh status"
  say "  Latest output:   shield-run.sh logs $location $calibration"
  say "  Outputs:         $STATE_ROOT"
  say "It keeps running if you log out."
}

cmd_status() {
  local names
  names="$(podman ps -a --filter name=^shield- --format '{{.Names}}')"
  if [[ -z "$names" ]]; then say "No SHIELD runs found."; return; fi
  while read -r name; do
    local location calibration state chunks last
    location="$(podman inspect --format '{{index .Config.Labels "shield.location"}}' "$name")"
    calibration="$(podman inspect --format '{{index .Config.Labels "shield.calibration"}}' "$name")"
    state="$(podman inspect --format '{{.State.Status}} (exit {{.State.ExitCode}})' "$name")"
    [[ "$state" == running* ]] && state="running"
    chunks="$(find "$STATE_ROOT/mcmc_runs/shield/$calibration/$location/cache/chain_1" -maxdepth 1 -name 'chain1_chunk*.Rdata' 2>/dev/null | wc -l | tr -d ' ')"
    last="$(podman logs --tail 1 "$name" 2>&1 | cut -c1-100)"
    say "$calibration $location: $state; checkpoints saved: $chunks"
    say "    last output: $last"
  done <<<"$names"
}

cmd_logs() { podman logs --tail 40 "$(container_name "$1" "$2")"; }

cmd_stop() {
  local name
  name="$(container_name "$1" "$2")"
  podman container exists "$name" || fail "no run found for $2 $1."
  # R ignores the polite stop signal, so podman forces it after 5 seconds.
  podman stop -t 5 "$name" >/dev/null 2>&1
  say "Stopped $2 for $1. Continue it later with: shield-run.sh resume $1 $2"
}

case "${1:-}" in
  setup)  cmd_setup ;;
  start)  [[ $# -eq 3 ]] || fail "usage: shield-run.sh start <location> <calibration>"; run_container fresh "$2" "$3" ;;
  resume) [[ $# -eq 3 ]] || fail "usage: shield-run.sh resume <location> <calibration>"; run_container resume "$2" "$3" ;;
  stop)   [[ $# -eq 3 ]] || fail "usage: shield-run.sh stop <location> <calibration>"; cmd_stop "$2" "$3" ;;
  logs)   [[ $# -eq 3 ]] || fail "usage: shield-run.sh logs <location> <calibration>"; cmd_logs "$2" "$3" ;;
  status) cmd_status ;;
  *) sed -n '2,15p' "$0" | sed 's/^# \{0,1\}//'; exit 64 ;;
esac
