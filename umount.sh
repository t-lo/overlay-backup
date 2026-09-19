#!/bin/bash
# vim: ts=2 et sw=2
#

set -euo pipefail

workdir="$(cd "$(dirname "$0")"; pwd)"
source "${workdir}/util.inc"

function usage() {
  echo "Usage: $0 [--settings <file>] [--netfs] <base-image-name>"
  echo "Unmount image stack of <base-image-name>, and optionally the network file system"
  echo "Note that you can use '--netfs' w/o '<base-image-name> to ONLY unmount the netfs. Potentially dangerous."
  settings_usage
}
# --

parse_cmdl 1 "${@}" || { usage; exit 1; }

report_base_error="true"
while [[ $# -ne 0 ]] ; do
  case "$1" in
    --netfs)
      report_base_error="false"
      function netfs_needs_mounting() {
        return 0
      }
    ;;
  esac
  shift
done

base="${ARGS[0]:-}"

init_trap "${BACKUP_IMAGES_MOUNT}" "${NETFS_MOUNT}"

if [[ -z "$base" ]]; then
  if $report_base_error ; then
    echo "ERROR: base image name missing"
    usage
  fi
  exit
fi

base_path="$(sanitise_image_path "${base}" "${BACKUP_IMAGES_DEST}")"

if [[ ! -f "${base_path}" ]] ; then
  echo "ERROR: backup image '${base_path}' not found."
  exit 1
fi

# Cleanup trap will handle unmounts
