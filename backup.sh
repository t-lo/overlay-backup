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
  echo "ERROR: Missing mandatory <name> argument."
  usage
  exit 1
fi

if [[ -z "${@}" ]] ; then
  echo "ERROR: Nothing to back up!"
  usage
  exit 1
fi

# --

announce "Preparing a new '${name}' backup at $(date)"
image_mount_base="${BACKUP_IMAGES_MOUNT}/${name}"

if [[ -n "${base}" ]] ; then
  base_path="$(sanitise_image_path "${base}" "${BACKUP_IMAGES_DEST}")"

  image="$(snapshot_image_name "${base}")"
  image_path="$(sanitise_image_path "${image}" "${BACKUP_IMAGES_DEST}")"
  echo "  Incremental backup to '${image}', image stack '${base_path}'"
else
  image="$(full_image_name "${name}")"
  image_path="$(sanitise_image_path "${image}" "${BACKUP_IMAGES_DEST}")"
  base="${image}"
  base_path="${image_path}"
  echo "  Full backup to '${image}'"
fi

cleanup_netfs="true"
netfs_needs_mounting "${NETFS_MOUNT}" || cleanup_netfs="false"

# backup image creation and mounting
init_trap "${image_mount_base}" "${NETFS_MOUNT}" "${image_path}"
mount_netfs "${NETFS_URI}" "${NETFS_MOUNT}" "${NETFS_MOUNTOPTS}"

if [[ "${image_path}" != "${base_path}" && ! -f "${base_path}" ]] ; then
  echo "ERROR: Incremental backup requested but base image '${base_path}' not found."
  exit 1
fi

create_fs_image "${image_path}" "${BACKUP_FSFILE_SIZE}"

if [[ "${base}" == "${image}" ]] ; then
  # We don't need overlayfs for a new full backup, just the datadir
  mount_fs_image "${image_path}" "${image_mount_base}/${image}"
else
  mount_image_stack "${base_path}" "${image_mount_base}"  
fi

dest="$(get_curr_datadir "${image_mount_base}" "${base}")"

# The Backup

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

announce "Images / snapshots stack:"
print_image_stack "${base_path}" "true" | sed 's:/[^ ]*/::g' | tee "$(dirname "${dest}")/image-stack.txt"

umount_image_stack "${image_mount_base}"
if $cleanup_netfs; then
  umount_netfs "${NETFS_MOUNT}"
fi

announce "Backup to '${image}' concluded successfully at $(date) "
init_trap "${image_mount_base}" "${NETFS_MOUNT}"
