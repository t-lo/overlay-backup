#!/bin/bash
# vim: ts=2 et sw=2

set -euo pipefail

workdir="$(cd "$(dirname "$0")"; pwd)"
source "${workdir}/util.inc"

function usage() {
  echo "$0 [--settings <file>] [--latest] [--base]"
  echo "   List all backup stacks, their file size, and their actual disk usage."
  echo "  --latest   Only list the latest stack insteal of all stacks."
  echo "  --base     Only list base (full backup) files."
  echo "             Can be combined with --latest to only list the latest full backup."
  echo "  --nostats  Print a plain files list w/o size and access stats."
  echo "  --usage    Also show total netfs usage."
}

parse_cmdl 0 "${@}" || { usage; exit 1; }

latest="false"
base="false"
net_usage="false"
nostats="false"
while [[ $# -ne 0 ]] ; do
  case "$1" in
    --latest) latest="true";;
    --base) base="true";;
    --usage) net_usage="true";;
    --nostats) nostats="true";;
  esac
  shift
done

if netfs_needs_mounting "${NETFS_MOUNT}" ; then
  trap "umount_netfs '${NETFS_MOUNT}'" EXIT
  mount_netfs "${NETFS_URI}" "${NETFS_MOUNT}" "${NETFS_MOUNTOPTS}"
fi

# First, get a list of all images present, sorted by date, with the most recent on top.
mapfile -t all_images < <(ls -1 "${BACKUP_IMAGES_DEST}/" | sort -r)

list_images=()
first_base="true"
for img in "${all_images[@]}"; do
  $latest && { $first_base || break; } # first stack is included, we're done

  if is_base_image "${img}"; then
    first_base="false"
  elif $base; then
    continue
  fi

  list_images+=( "${BACKUP_IMAGES_DEST}/$img" )
done

[[ -n "${list_images[@]}" ]] || list_images+=( "${BACKUP_IMAGES_DEST}/" )

echo " --- File list in backup images directory '${BACKUP_IMAGES_DEST}'" >&2
echo "">&2
if $nostats; then
  # Print the array backwards to mimic "ls" output (most recent item last)
  for ((i=${#list_images[@]}; i>0; i--)); do
    echo "$(basename ${list_images[$i-1]})"
  done
else
  ls -lsh "${list_images[@]}" | sed "s;${BACKUP_IMAGES_DEST}/;;"
fi
echo "">&2

if $net_usage; then
  echo " --- NETFS usage:">&2
  df -h "${NETFS_MOUNT}/${UTIL_NETFS_MOUNTFLAG_FILE}" | tail -n "-1"
  echo "">&2
fi
