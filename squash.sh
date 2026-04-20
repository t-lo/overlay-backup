#!/bin/bash
# vim: ts=2 et sw=2

set -euo pipefail

scriptdir="$(cd "$(dirname "$0")"; pwd)"
source "${scriptdir}/util.inc"
source "${scriptdir}/settings.env"

# --

function usage() {
  echo "$0 <base>"
  echo "  Squash all incremental backups of <base> into one new incremental backup."
  echo "  After squashing succeeded, remove all previous incremental backups."

}
# --

base="${1:-}"
if [[ -z "$base" ]] ; then
  usage
  exit 0
fi

# --
# Init and basic sanity

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

declare -a snapshots
for s in $(print_image_stack "${base_path}"); do
  echo "$s" | grep -q "${UTIL_IMAGE_SNAPSHOT_SEPARATOR}" || continue
  snapshots+=( "$s" )
done

if [[ 0 -ge "${#snapshots[@]}" ]] ; then
  echo "ERROR: Base image '${base}' does not have any snapshots to squash."
  exit 1
fi

# --
# Mounting

# Mount the stack before creating a WIP image to prevent WIP getting the merged overlay mounted.
mount_image_stack "${base_path}" "${BACKUP_IMAGES_MOUNT}"  
src="$(get_backup_dir "${BACKUP_IMAGES_MOUNT}")"

image="$(snapshot_image_name "${base}")"
start_wip_image "${image}" "${SNAPSHOT_BACKUP_FSFILE_SIZE}" "${BACKUP_IMAGES_DEST}"

image_path="$(print_image_stack "${base_path}" | tail -n1)"
image_mount_point="${BACKUP_IMAGES_MOUNT}/$((${#snapshots[@]} + 1))"
mount_fs_image "${image_path}" "${image_mount_point}"
echo -e "${image}\n${base}\n" > "${image_mount_point}/${UTIL_IMAGE_STACK_FILE}"

# _mount_overlay uses relative directories to keep the mount opts short
base_image_datadir="./0/${UTIL_IMAGE_DATADIR}"
rel_image_mountdir="$(basename "${image_mount_point}")"
do_mount_overlay "${BACKUP_IMAGES_MOUNT}" "${image}" "${rel_image_mountdir}" "${base_image_datadir}" "false"

# With the WIP image mounted this will return the WIP image's merged dir.
dest="$(get_backup_dir "${BACKUP_IMAGES_MOUNT}")"

echo
announce "Squashing '${base}' and all snapshots to '${image}'."
echo

changes_file="${image_mount_point}/changes.txt"

rm -f "${changes_file}"
set +e
rsync --prune-empty-dirs --archive --delete \
      --times --update --modify-window 1 \
      --human-readable --whole-file \
      --info=progress2 \
      --ignore-errors \
      --log-file "${changes_file}" \
      --inplace "${src}/" "${dest}/"

ret="$?"
case "$ret" in
  0)  echo "  ==> Transfer successful.";;
  24) echo "  ==> 'Partial transfer due to vanished source files' (code 24). This is expected; ignoring.";;
  *)  echo "  ERROR: Unexpected rysnc error #$ret."; exit $ret;;
esac
set -e

ts="$(date --rfc-3339=seconds | sed -e 's/ /_/' -e 's/:/-/g' -e 's/+.*//')"
touch "$(dirname "${dest}")/create-success-${ts}"

umount_image_stack "${BACKUP_IMAGES_MOUNT}"
finish_wip_image "${image}" "${BACKUP_IMAGES_DEST}"

echo
announce "Removing all previous snapshots."
echo
for s in "${snapshots[@]}"; do
  s_file="$(sanitise_image_path "${s}" "${BACKUP_IMAGES_DEST}")"
  rm -v "${s_file}"
done

echo
announce "Suqash successful."
echo
echo "  NETFS usage after backup"
df -h "${NETFS_MOUNT}/${UTIL_NETFS_MOUNTFLAG_FILE}"
echo
