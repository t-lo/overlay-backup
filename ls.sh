#!/bin/bash
# vim: ts=2 et sw=2

set -euo pipefail

workdir="$(cd "$(dirname "$0")"; pwd)"
source "${workdir}/util.inc"
source "${workdir}/settings.env"

if netfs_needs_mounting "${NETFS_MOUNT}" ; then
  trap "umount_netfs '${NETFS_MOUNT}'" EXIT
  mount_netfs "${NETFS_URI}" "${NETFS_MOUNT}" "${NETFS_MOUNTOPTS}"
fi
echo " --- File list in backup images directory '${BACKUP_IMAGES_DEST}/'"
echo
ls -1sh "${BACKUP_IMAGES_DEST}"/ | grep -v '.mount-check'
echo
echo " --- NETFS usage"
df -h "${NETFS_MOUNT}/${UTIL_NETFS_MOUNTFLAG_FILE}"
echo
