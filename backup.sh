#!/bin/bash
# vim: ts=2 et sw=2
#

set -euo pipefail

scriptdir="$(cd "$(dirname "$0")"; pwd)"
source "${scriptdir}/util.inc"
source "${scriptdir}/settings.env"

# --

function usage() {
  echo "$0 <name> [<base>] -- <src> [<src2>] ..."
  echo "  Create a new FS image file backup of <name>."
  echo "   If <base> was provided, create a new incremental backup based on stack <base>."
  echo "  Everything after the '--' separator will be backed up."
}
# --

#
# Process command line arguments
#

name=""
base=""
cmdline="${@}"
while [[ "$#" -gt 0 ]] ; do
  case "$1" in
    --) shift; break;;
    *)  if [[ -z "${name}" ]] ; then
          name="$1"
        elif [[ -z "${base}" ]] ; then
          base="$1"
        else
          echo "ERROR: Spurious positional argument '$1'. Full command line: '${cmdline}'"
          usage
          exit 1
        fi
  esac
  shift
done

if [[ -z "$name" ]] ; then
  usage
  exit 0
fi

if [[ -z "${@}" ]] ; then
  echo "ERROR: Nothing to back up!"
  usage
  exit 1
fi

# --

ts_start="$(ts)"
announce "Preparing a new '${name}' backup at ${ts_start}"

if [[ -n "${base}" ]] ; then
  image="$(snapshot_image_name "${base}")"
  fs_file_size="${SNAPSHOT_BACKUP_FSFILE_SIZE}"
  echo "  Incremental backup to '${image}', image stack '${base}'"
else
  image="$(full_image_name "${name}")"
  base="${image}"
  fs_file_size="${FULL_BACKUP_FSFILE_SIZE}"
  echo "  Full backup to '${image}'"
fi

# Prepare backup image and snapshot stack

init_trap "${BACKUP_IMAGES_MOUNT}" "${NETFS_MOUNT}" "${BACKUP_IMAGES_DEST}"
mount_netfs "${NETFS_URI}" "${NETFS_MOUNT}" "${NETFS_MOUNTOPTS}"

base_path="$(sanitise_image_path "${base}" "${BACKUP_IMAGES_DEST}")"
if [[ "${image}" != "${base}" && ! -f "${base_path}" ]] ; then
  echo "ERROR: Incremental backup requested but base image '${base_path}' not found."
  exit 1
fi

start_wip_image "${image}" "${fs_file_size}" "${BACKUP_IMAGES_DEST}"
mount_image_stack "${base_path}" "${BACKUP_IMAGES_MOUNT}"  

if [[ "${image}" != "${base}" ]] ; then
  dest="$(get_merged_dir "${BACKUP_IMAGES_MOUNT}" "${base}")"
else
  dest="$(get_data_dir "${BACKUP_IMAGES_MOUNT}" "${base}")"
fi

# Commence backup

announce "Backing up to '$dest'"

img_basedir="$(dirname "${dest}")"
set +e
rm -f "${img_basedir}/changes.txt"
rsync --prune-empty-dirs --archive --delete \
      --verbose --human-readable --whole-file \
      --info=progress2 \
      --ignore-errors \
      --log-file "${img_basedir}/changes.txt" \
      --inplace "${@}" "${dest}"
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

umount_image_stack "${BACKUP_IMAGES_MOUNT}"
finish_wip_image "${image}" "${BACKUP_IMAGES_DEST}"

echo
echo
ts_end="$(ts)"
announce "Backup concluded successfully."
echo "  Image : ${image}"
echo "  Start : ${ts_start}"
echo "  End   : ${ts_end}"
echo "  NETFS usage after backup"
df -h "${NETFS_MOUNT}/${UTIL_NETFS_MOUNTFLAG_FILE}"
echo
echo
