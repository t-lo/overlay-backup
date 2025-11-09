#!/bin/bash
# vim: ts=2 et sw=2
#

set -euo pipefail

workdir="$(cd "$(dirname "$0")"; pwd)"
source "${workdir}/util.inc"
source "${workdir}/settings.env"

base="$1"
base_path="$(sanitise_image_path "${base}" "${BACKUP_IMAGES_DEST}")"

init_trap "${BACKUP_IMAGES_MOUNT}" "${NETFS_MOUNT}"

netumount="--netfs"
netfs_needs_mounting "${NETFS_MOUNT}" || netumount=""

mount_netfs "${NETFS_URI}" "${NETFS_MOUNT}" "${NETFS_MOUNTOPTS}"

# Check for presence of base_path image only after NETFS was mounted.
if [[ ! -f "${base_path}" ]] ; then
  echo "ERROR: backup image '${base_path}' not found."
  exit 1
fi

mount_image_stack "$base_path" "${BACKUP_IMAGES_MOUNT}" "true"

datadir="$(get_merged_dir "${BACKUP_IMAGES_MOUNT}" "${base_path}")"
echo "==> MOUNT COMPLETE: Latest '$base' state is now available at '${datadir}'."
echo "Run './umount.sh ${netumount} \"${base}\"' to unmount."

trap "" EXIT
