#!/bin/bash
# vim: ts=2 et sw=2
#

set -euo pipefail

workdir="$(cd "$(dirname "$0")"; pwd)"
source "${workdir}/util.inc"

function usage() {
  echo "Usage:"
  echo " $0 [--settings <file>] <base-image-name> [deep]"
  echo "    Mount full image stack of <base-image-name>."
  echo "    If 'deep' is provided after the image, all snapshots' overlays will be mounted"
  echo " $0 [--settings <file>] netfs"
  echo "    Only mount the netfs."
  settings_usage
}
# --

parse_cmdl 2 "${@}" || { usage; exit 1; }
echo "${ARGS[@]}"

base="${ARGS[0]:-}"
if [[ -z "$base" ]] ; then
  echo "ERROR: base image name missing."
  usage
  exit 1
fi

deep="false"
if [[ "${ARGS[1]:-}" == "deep" ]] ; then
  deep="true"
fi

base_path="$(sanitise_image_path "${base}" "${BACKUP_IMAGES_DEST}")"

init_trap "${BACKUP_IMAGES_MOUNT}" "${NETFS_MOUNT}"

netumount="--netfs"
netfs_needs_mounting "${NETFS_MOUNT}" || netumount=""

mount_netfs "${NETFS_URI}" "${NETFS_MOUNT}" "${NETFS_MOUNTOPTS}"

if [[ "$base" == "netfs" ]] ; then
  echo "==> Mount complete; netfs available at '${NETFS_MOUNT}'"
  base=""
else
  # Check for presence of base_path image only after NETFS was mounted.
  if [[ ! -f "${base_path}" ]] ; then
    echo "ERROR: base '${base}' not found at '${base_path}.'"
    exit 1
  fi

  mount_image_stack "$base_path" "${BACKUP_IMAGES_MOUNT}" "true" "${deep}"
  echo "==> MOUNT COMPLETE: Latest '$base' state is now available at:"
  echo -n "    "; get_backup_dir "${BACKUP_IMAGES_MOUNT}"
fi

echo "Run './umount.sh ${netumount} --settings ${SETTINGS_FILE} ${base}' to unmount."

trap "" EXIT
