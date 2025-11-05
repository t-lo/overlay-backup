#!/bin/bash
# vim: ts=2 et sw=2
#

set -euo pipefail

workdir="$(cd "$(dirname "$0")"; pwd)"
source "${workdir}/util.inc"
source "${workdir}/settings.env"

if [[ "${1}" == "--netfs" ]] ; then
  function netfs_needs_mounting() {
    return 0
  }
  shift
fi

base="$1"
base_path="$(sanitise_image_path "${base}" "${BACKUP_IMAGES_DEST}")"
image_mount_base="${BACKUP_IMAGES_MOUNT}/${base}"

init_trap "${image_mount_base}" "${NETFS_MOUNT}"

if [[ ! -f "${base_path}" ]] ; then
  echo "ERROR: backup image '${base_image}' not found."
  exit 1
fi

# Cleanup trap will handle unmounts
