# Container-engine settings shared by the SHIELD canary and pilot scripts.
# Sourced, not executed.
#
# CONTAINER_ENGINE     docker (CI default) or podman (rootless, RHEL team servers).
#                      Rootless podman uses --userns=keep-id, so files the
#                      container writes keep the invoking user as owner.
# SHIELD_MOUNT_RELABEL SELinux relabel for local bind mounts (e.g. "shared").
#                      Skipped automatically for CIFS mounts such as the NAS,
#                      which can't be relabeled; containers reach those only
#                      when the host enables the virt_use_samba boolean.
# SHIELD_KEEP_GROUPS   true passes the user's supplementary groups (e.g. jheem)
#                      into a rootless podman container, needed to write to the
#                      group-writable NAS.

engine="${CONTAINER_ENGINE:-docker}"
engine_args=()
if [[ "$engine" == podman && "$(id -u)" != 0 ]]; then
  engine_args+=(--userns=keep-id)
  if [[ "${SHIELD_KEEP_GROUPS:-false}" == true ]]; then
    engine_args+=(--group-add keep-groups)
  fi
fi

# Extra --mount options for a bind source: the relabel, unless it's on CIFS.
mount_opts() {
  local fs
  [[ -n "${SHIELD_MOUNT_RELABEL:-}" ]] || return 0
  fs=$(stat -f -c %T "$1" 2>/dev/null || echo unknown)
  case "$fs" in
    cifs|smb2|smb3) ;;
    *) printf ',relabel=%s' "$SHIELD_MOUNT_RELABEL" ;;
  esac
}
