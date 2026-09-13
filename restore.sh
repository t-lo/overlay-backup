#!/bin/bash
# vim: ts=2 et sw=2
#

set -euo pipefail

scriptdir="$(cd "$(dirname "$0")"; pwd)"
source "${scriptdir}/util.inc"

function usage() {
  echo "$0 [--settings <file>] <base> <dest>"
  echo "  Restore FS image backup stack <base> to <dest>."
  echo "  Stack <base> must exist in the backup, and destination directory <dest> must exist locally."
  settings_usage
}
# --

#
# Process command line arguments
#

parse_cmdl 2 "${@}" || { usage; exit 1; }

base="${ARGS[0]:-}"
dest="${ARGS[1]:-}"

if [[ -z "$base" ]] ; then
  echo "ERROR: base image name is missing."
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
  echo "ERROR: Base image '${base_path}' not found."
  exit 1
fi

if ! is_base_image "${base}"; then
  echo "ERROR: Image '${base}' must be a base image. Snapshots are not supported."
  exit 1
fi

mount_image_stack "${base_path}" "${BACKUP_IMAGES_MOUNT}" "true" 

src="$(get_backup_dir "${BACKUP_IMAGES_MOUNT}")"

cb_restore_pre "${base}" "${src}" "${dest}"

announce "Restoring '${src}' to '${dest}'"

img_basedir="$(dirname "${dest}")"

log_file="${dest}/restore.log"
touch "${dest}/restore-start-${ts_start}"
rsync --archive \
      --info=progress2 \
      --human-readable --whole-file \
      --ignore-errors --inplace \
      --log-file "${log_file}" \
      "${src}"/* "${dest}"/

cb_restore_post "${base}" "${src}" "${dest}"

latest_image="$(print_image_stack "${base_path}"|tail -n1)"
echo "$(basename "${latest_image}")" > "${dest}/restore-image.txt"

ts="$(date --rfc-3339=seconds | sed -e 's/ /_/' -e 's/:/-/g' -e 's/+.*//')"
touch "${dest}/restore-success-${ts}"

umount_image_stack "${BACKUP_IMAGES_MOUNT}"

echo
ts_end="$(ts)"
announce "Restore concluded successfully."
echo "  Start : ${ts_start}"
echo "  End   : ${ts_end}"
echo "  Details in '${log_file}'"
echo
