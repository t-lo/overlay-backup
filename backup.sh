#!/bin/bash
# vim: ts=2 et sw=2 syn=bash

set -euo pipefail

scriptdir="$(cd "$(dirname "$0")"; pwd)"
source "${scriptdir}/util.inc"

# --

function usage() {
  echo "$0 [--settings <file>] [<base>]"
  echo "  Create a new FS image file backup based on the settings in 'settings.env'."
  echo "   <base>            - Create a new incremental backup based on stack <base>."
  echo "                       If omitted, a new full backup is created."
  settings_usage
  echo "  The settings file defines what to back up; it is sourced by $0."
  echo "  Optionally, pre- and post-backup callbacks may be defined there, too."
  echo "  Check out 'example.settings.env' for more information."
}
# --

parse_cmdl 1 "${@}" || { usage; exit 1; }
base="${ARGS[0]:-}"

# --
# image prep

ts_start="$(ts)"
announce "Preparing a new '${BASENAME}' backup at ${ts_start}"
echo

if [[ -n "${base}" ]] ; then
  image="$(snapshot_image_name "${base}")"
  fs_file_size="${SNAPSHOT_BACKUP_FSFILE_SIZE}"
  echo "  Incremental backup to '${image}', image stack '${base}'"
else
  image="$(full_image_name "${BASENAME}")"
  base="${image}"
  fs_file_size="${FULL_BACKUP_FSFILE_SIZE}"
  echo "  Full backup to '${image}'"
fi

init_trap "${BACKUP_IMAGES_MOUNT}" "${NETFS_MOUNT}" "${BACKUP_IMAGES_DEST}"
mount_netfs "${NETFS_URI}" "${NETFS_MOUNT}" "${NETFS_MOUNTOPTS}"

base_path="$(sanitise_image_path "${base}" "${BACKUP_IMAGES_DEST}")"
if [[ "${image}" != "${base}" ]] ; then
  if [[ ! -f "${base_path}" ]] ; then
    echo "ERROR: Incremental backup requested but base image '${base_path}' not found."
    exit 1
  elif ! is_base_image "${base}"; then
    echo "ERROR: Base image '${base}' must be a base image. Snapshots are not supported."
    exit 1
  fi
fi

start_wip_image "${image}" "${fs_file_size}" "${BACKUP_IMAGES_DEST}"
mount_image_stack "${base_path}" "${BACKUP_IMAGES_MOUNT}"  

dest="$(get_backup_dir "${BACKUP_IMAGES_MOUNT}")"

# --
# Handle backup sources

cb_backup_pre "${BASENAME}" "${base}" "${image}" "${dest}" "--" "${@:-}"

src=()
if [[ -n "${backup_sources[@]}" ]] ; then
  src+=( "${backup_sources[@]}" )
else
  if [[ -z "${@:-}" ]] ; then
    echo "ERROR: Nothing to back up!"
    usage
    exit 1
  fi
  src+=( "${@}" )
fi


# --
# Commence backup


announce "Backing up to '$dest'"
echo "Sources:"
echo " ---"
printf "%s\n" "${src[@]}"
echo " ---"
echo

img_basedir="$(dirname "${dest}")"
changes_file="${img_basedir}/changes.txt"
set +e
rm -f "${changes_file}"
rsync --prune-empty-dirs --archive --delete \
      --times --update --modify-window 1 \
      --human-readable --whole-file \
      --info=progress2 \
      --ignore-errors \
      --log-file "${changes_file}" \
      --inplace "${src[@]%/}" "${dest}"
                # ^^^^  Remove trailing "/" from paths to ensure incremental backups remain uniform
ret="$?"
case "$ret" in
  0)  echo "  ==> Transfer successful.";;
  24) echo "  ==> 'Partial transfer due to vanished source files' (code 24). This is expected; ignoring.";;
  *)  echo "  ERROR: Unexpected rysnc error #$ret."; exit $ret;;
esac
set -e

ts="$(date --rfc-3339=seconds | sed -e 's/ /_/' -e 's/:/-/g' -e 's/+.*//')"
touch "$(dirname "${dest}")/create-success-${ts}"

echo "  --- Images / snapshots stack:"
cat "${img_basedir}/${UTIL_IMAGE_STACK_FILE}"
echo "  ---"


cb_backup_post "${BASENAME}" "${base}" "${image}" "${dest}"

umount_image_stack "${BACKUP_IMAGES_MOUNT}"
finish_wip_image "${image}" "${BACKUP_IMAGES_DEST}"

echo
echo
ts_end="$(ts)"
announce "Backup concluded successfully."
echo "  Image : ${image}"
echo "  Start : ${ts_start}"
echo "  End   : ${ts_end}"
echo "  Changes captured in '${changes_file}'"
echo
echo "  NETFS usage after backup"
df -h "${NETFS_MOUNT}/${UTIL_NETFS_MOUNTFLAG_FILE}"
echo
announce "DONE"
