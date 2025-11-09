#!/bin/bash
# vim: ts=2 et sw=2
#

set -euo pipefail

workdir="$(cd "$(dirname "$0")"; pwd)"
source "${workdir}/util.inc"
source "${workdir}/settings.env"

if [[ "${1:-}" == "--netfs" ]] ; then
  function netfs_needs_mounting() {
    return 0
  }
  shift
fi

if [[ "$#" -lt 1 ]] ; then
  echo "Usage: $0 [--netfs] <base-image-name>"
  echo "Unmount image stack of <base-image-name>, and optionally the network file system"
  exit
fi

base="$1"
base_path="$(sanitise_image_path "${base}" "${BACKUP_IMAGES_DEST}")"

init_trap "${BACKUP_IMAGES_MOUNT}" "${NETFS_MOUNT}"

if [[ ! -f "${base_path}" ]] ; then
  echo "ERROR: backup image '${base_path}' not found."
  exit 1
fi

# Cleanup trap will handle unmounts
