#!/bin/bash
# vim: ts=2 et sw=2

set -euo pipefail

workdir="$(cd "$(dirname "$0")"; pwd)"
source "${workdir}/util.inc"
source "${workdir}/settings.env"

prune="$1"
prune_path="$(sanitise_image_path "${prune}" "${BACKUP_IMAGES_DEST}")"

if netfs_needs_mounting "${NETFS_MOUNT}" ; then
  trap "umount_netfs '${NETFS_MOUNT}'" EXIT
  mount_netfs "${NETFS_URI}" "${NETFS_MOUNT}" "${NETFS_MOUNTOPTS}"
fi

# Check for presence of prune_path image only after NETFS was mounted.
if [[ ! -f "${prune_path}" ]] ; then
  echo "ERROR: backup image '${prune_path}' not found."
  exit 1
fi

base_image="$(full_from_snapshot_name "${prune_path}")"

dependent="false"
for img in $(print_image_stack "${base_image}"); do
  if [[ "${prune_path}" == "${img}" ]] ; then
    echo "  --- Deleting image '${img}'"
    rm "${img}"
    dependent="true"
    continue
  elif [[ "$dependent" == "true" ]] ; then
    echo "    ==> Deleting dependent image '${img}'"
    rm "${img}"
  fi
done
