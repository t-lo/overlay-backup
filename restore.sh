#!/bin/bash
# vim: ts=2 et sw=2
#

set -euo pipefail

scriptdir="$(cd "$(dirname "$0")"; pwd)"
source "${scriptdir}/util.inc"

function cb_restore_pre()  { true; }
function cb_restore_post() { true; }
source "${scriptdir}/settings.env"

# --

function usage() {
  echo "$0 <base> <dest>"
  echo "  Restore FS image backup stack <base> to <dest>."
  echo "  Stack <base> must exist in the backup, and destination directory <dest> must exist locally."
}
# --

#
# Process command line arguments
#

base="${1:-}"
dest="${2:-}"

if [[ -z "$base" ]] ; then
  usage
  exit 0
fi

if [[ ! -d "${dest}" ]] ; then
  echo "ERROR: Restore target directory '${dest}' does not exist!"
  usage
  exit 1
fi

# --

ts_start="$(ts)"
announce "Starting restore of '${base}'"


init_trap "${BACKUP_IMAGES_MOUNT}" "${NETFS_MOUNT}" "${BACKUP_IMAGES_DEST}"
mount_netfs "${NETFS_URI}" "${NETFS_MOUNT}" "${NETFS_MOUNTOPTS}"


base_path="$(sanitise_image_path "${base}" "${BACKUP_IMAGES_DEST}")"
if [[ ! -f "${base_path}" ]] ; then
  echo "ERROR: Incremental backup requested but base image '${base_path}' not found."
  exit 1
fi

mount_image_stack "${base_path}" "${BACKUP_IMAGES_MOUNT}" "true" 

src="$(get_backup_dir "${BACKUP_IMAGES_DEST}")"

cb_restore_pre "${base}" "${src}" "${dest}"

announce "Restoring '${src}' to '${dest}'"

img_basedir="$(dirname "${dest}")"

rsync --archive \
      --info=progress2 \
      "${src}"/* "${dest}"/

cb_restore_post "${base}" "${src}" "${dest}"

ts="$(date --rfc-3339=seconds | sed -e 's/ /_/' -e 's/:/-/g' -e 's/+.*//')"
touch "${dest}/restore-success-${ts}"

umount_image_stack "${BACKUP_IMAGES_MOUNT}"

echo
ts_end="$(ts)"
announce "Restore concluded successfully."
echo "  Start : ${ts_start}"
echo "  End   : ${ts_end}"
echo
