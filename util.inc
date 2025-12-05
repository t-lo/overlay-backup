#!/bin/bash
# vim:ts=2:et:sw=2:syn=bash
#

UTIL_IMAGE_DATADIR="data"
UTIL_IMAGE_WORKDIR=".work"
UTIL_IMAGE_MERGEDIR="merged"

UTIL_IMAGE_STACK_FILE="image-stack.txt"
UTIL_IMAGE_WIP_SUBDIR=".wip"

UTIL_IMAGE_SNAPSHOT_SEPARATOR="snapshot"
UTIL_NETFS_MOUNTFLAG_FILE=".mount-check"

# Mount command defaults; override in settings.env.
mount_cmd_netfs=( "mount.cifs" )
mount_cmd_fsimg=( "mount" )
# Work around 256 bytes mountopts size limit, see example.settings.env and https://github.com/util-linux/util-linux/issues/2287
mount_cmd_overlay=( "busybox" "mount" )

function ts() {
  date --rfc-3339=seconds | sed -e 's/ /_/' -e 's/:/-/g' -e 's/+.*//'
}
# --

function announce() {
  echo "#### $(ts) ####  ${@}"
}
# --

function snapshot_image_name() {
  local base="$1"
  local ts="$(ts)"
  echo  "${base}-${UTIL_IMAGE_SNAPSHOT_SEPARATOR}-${ts}"
}
# --

function full_image_name() {
  local base="$1"
  local ts="$(date --rfc-3339=seconds | sed -e 's/ /_/' -e 's/:/-/g' -e 's/+.*//')"
  echo  "${base}-${ts}"
}
# --

function full_from_snapshot_name() {
  local snap="$1"
  echo "${snap%${UTIL_IMAGE_SNAPSHOT_SEPARATOR}*}"
}
# --

function sanitise_image_path() {
  local img="$1"
  local img_store="$2"
  echo "${img_store}/$(basename "${img}")"
}
# --

function netfs_needs_mounting() {
  local mountpoint="${1}"
  [[ ! -f "${mountpoint}/${UTIL_NETFS_MOUNTFLAG_FILE}" ]]
}
# --

function mount_netfs() {
  local uri="${1}"
  local mountpoint="${2}"
  local mountopts="${3}"

  if netfs_needs_mounting "${mountpoint}" ; then
    echo "  Mounting net FS to '${mountpoint}'"
    mkdir -p "${mountpoint}"
    local opts=( "-o" "${mountopts}" "${uri}" "${mountpoint}" )
    "${mount_cmd_netfs[@]}" "${opts[@]}"
    touch "${mountpoint}/${UTIL_NETFS_MOUNTFLAG_FILE}"
  fi
}
# --

function umount_netfs() {
  local mount_point="$1"

  if mountpoint -q "${mount_point}"; then
    echo "  Syncing and unmounting NETFS '${mount_point}'"
    sync --file-system "${mount_point}"/.*
    umount_loop "${mount_point}"
  else
    echo "  NETFS '${mount_point}' not mounted"
  fi
}
# --

function mount_fs_image() {
  local fs_image="${1}"
  local mount_point="${2}"
  local ro="${3:-}"

  if [[ "${ro}" == "true" ]] ; then
    ro="-o ro"
  else
    ro=""
  fi

  echo "  Mount '${mount_point}'"
  mkdir -p "${mount_point}"
  "${mount_cmd_fsimg[@]}" -o loop \
        ${ro} \
        -o context='system_u:object_r:httpd_sys_content_t:s0' \
        "${fs_image}" "${mount_point}"

  function check_create_dir() {
    local d="$1"
    if [[ ! -d "${d}" ]] ; then
      echo "    $(basename "${d}") missing in image; creating it."
      mkdir -p "${d}"
    fi
  }

  check_create_dir "${mount_point}/${UTIL_IMAGE_DATADIR}"
  check_create_dir "${mount_point}/${UTIL_IMAGE_MERGEDIR}"
  check_create_dir "${mount_point}/${UTIL_IMAGE_WORKDIR}"
}
# --

function umount_loop() {
  local mount_point="$1"

  # Loop until transient "device busy" disappears
  umount "${mount_point}" || echo "    ...retrying in 1s"
  while mountpoint -q "${mount_point}"; do
    sleep 1
    umount "${mount_point}" || echo "    ...retrying in 1s"
  done
}
# --

function umount_sync() {
  local mnt_dir="$1"

  if mountpoint -q "${mnt_dir}" ; then
    echo "  Syncing and unmounting '${mnt_dir}'"
    sync --file-system "${mnt_dir}"/*
    umount_loop "${mnt_dir}"
  fi
}
# --
function wip_image_path() {
  local images_storage_dir="${1}"
  echo "${images_storage_dir}/${UTIL_IMAGE_WIP_SUBDIR}"
}
# --

function start_wip_image() {
  local filename="${1}"
  local filesize="${2}"
  local images_storage_dir="${3}"

  local dest_path="$(wip_image_path "${images_storage_dir}")"
  mkdir -p "${dest_path}"
  local image_path="${dest_path}/${filename}"

  echo "  Creating WIP FS image '${image_path}'"
  dd of="${image_path}" bs="${filesize}" seek=1 count=0
  mkfs.ext4 -m0 "${image_path}"
}
# --

function finish_wip_image() {
  local filename="${1}"
  local images_storage_dir="${2}"

  local wip_dir="$(wip_image_path "${images_storage_dir}")"
  local src=${wip_dir}"/${filename}"
  local dest="${images_storage_dir}/${filename}"

  echo "  Finishing backup image"
  mv "${src}" "${dest}"
  rmdir "${wip_dir}"
}
# --

# Print a list ("stack") of images based on a base image name, sorted alphabetically.
# If a WIP image exists, it is included in the list.
# By default, the stack is sorted oldest-to-newest, with the WIP image being the last.
# If "reverse" is true, this order is reversed.
function print_image_stack() {
  local base_image="${1}"
  local reverse="${2:-}"

  local wip_path="$(dirname "${base_image}")/${UTIL_IMAGE_WIP_SUBDIR}"
  local wip_match="${wip_path}/$(basename "${base_image}")"

  # We use "ls" because it sorts alphabetically by default,
  #  and mount order by timestamp is important for overlayfs to work.
  if [[ -n "${reverse}" ]] ; then
    reverse="--reverse"
    ls -1 "${wip_match}"* 2>/dev/null || true
  fi

  ls -1 ${reverse} "${base_image}"* 2>/dev/null || true

  if [[ -z "${reverse}" ]] ; then
    ls -1 "${wip_match}"* 2>/dev/null || true
  fi
}
# --

function print_mount_stack() {
  local image_mnt_topdir="${1}"
  local reverse="${2:-}"

  if [[ -n "${reverse}" ]] ; then
    reverse="--reverse"
  fi

  # "natural sort" so 10 comes after 2
  ls -dv1 ${reverse} "${image_mnt_topdir}/"* 2>/dev/null
}
# --

function get_data_dir() {
  local image_mnt_topdir="${1}"

  local latest_mount="$(print_mount_stack "${image_mnt_topdir}" | tail -n 1)"
  echo "${latest_mount}/${UTIL_IMAGE_DATADIR}"
}
# --

function get_merged_dir() {
  local image_mnt_topdir="${1}"

  local latest_mount="$(print_mount_stack "${image_mnt_topdir}" | tail -n 1)"
  echo "${latest_mount}/${UTIL_IMAGE_MERGEDIR}"
}
# --

function get_backup_dir() {
  local image_mnt_topdir="${1}"

  local latest="$(basename "$(print_mount_stack "${image_mnt_topdir}" | tail -n 1)")"
  local base="$(full_from_snapshot_name "${latest}")"

  if [[ "${base}" != "${latest}" ]] ; then
    get_merged_dir "${BACKUP_IMAGES_MOUNT}" "${base}"
  else
    get_data_dir "${BACKUP_IMAGES_MOUNT}" "${base}"
  fi
}
# --

function image_from_mountpoint() {
  local mountpoint="$1"
  head -n1 "${mountpoint}/${UTIL_IMAGE_STACK_FILE}"
}
# --

function overlay_check_opts() {
  local opts="${@}"

  local len="$(echo -n "${opts}" | wc -c)"
  local maxlen="$(getconf PAGE_SIZE)"

  if [[ "${len}" -gt "${maxlen}" ]] ; then
    echo "ERROR: overlayfs mount options command line is longer than PAGE_SIZE"
    echo " ('${len}' vs. '${maxlen}'). Overlayfs mount would fail."
    exit 1
  fi
}
# --

function _mount_overlay() {
  local overlay_dir="$1"
  local lowerdirs="$2"
  local ro="$3"

  local upperdir="./${overlay_dir}/${UTIL_IMAGE_DATADIR}"
  local merged="./${overlay_dir}/${UTIL_IMAGE_MERGEDIR}"
  local work_dir="${overlay_dir}/${UTIL_IMAGE_WORKDIR}"
  local opts=()

  # Set overlay security context if SELinux is not disabled
  if [[ "$(getenforce)" != Disabled ]] ; then
    opts=( "-o" "context=system_u:object_r:httpd_sys_content_t:s0" )
  fi

  if [[ "${ro}" == "true" ]] ; then
    opts+=( "-o" "lowerdir=${upperdir}:${lowerdirs}" )
  else
    opts+=( "-o" "lowerdir=${lowerdirs},upperdir=${upperdir},workdir=${work_dir}" )
  fi

  overlay_check_opts "${opts[@]}"

  echo "  Overlay: '${upperdir}' :: '${lowerdirs}'"
  "${mount_cmd_overlay[@]}" -t overlay "${opts[@]}" "${name}" "${merged}"
}
# --

function mount_overlay() {
  local image_mnt_topdir="$1"
  local overlay_topdir="$2"
  local ro="${3:-}"

  local overlay_dir="$(basename "${overlay_topdir}")"
  local name="$(image_from_mountpoint "${overlay_topdir}")"

  local dir
  declare -A mount_map
  for dir in $(print_mount_stack "${image_mnt_topdir}"); do
    local img="$(image_from_mountpoint "${dir}")"
    mount_map[${img}]="./$(basename "${dir}")"
  done

  local lowerdirs=""
  local s_img
  for s_img in $(cat "${overlay_topdir}/${UTIL_IMAGE_STACK_FILE}"); do
    [[ "${s_img}" != "${name}" ]] || continue
    lowerdirs="${lowerdirs}${mount_map[$s_img]}/data:"
  done
  lowerdirs="${lowerdirs%:}"

  (
    set -euo pipefail
    cd "${image_mnt_topdir}"
    _mount_overlay "${overlay_dir}" "${lowerdirs}" "${ro}"
  )
}
# --

# The images will be mounted to sub-directories in image_mnt_topdir:
#   <base>-<ts>                     ==> $image_mnt_topdir/0
#   <base>-<ts>-snapshot-<ts1>      ==> $image_mnt_topdir/1
#   <base>-<ts>-snapshot-<ts2>      ==> $image_mnt_topdir/2
#   ...
# Using numbered mount points shortens the overlayfs kernel mount command line which has
#  a fixed size limit of PAGE_SIZE-1 (see mount_overlay).
function mount_image_stack() {
  local base_image="${1}"
  local image_mnt_topdir="${2}"
  local ro="${3:-}"
  local deep="${4:-}"

  announce "Mounting image stack for '${base_image}'"

  local count=0
  local img
  local stack=""
  local stack_size="$(print_image_stack "${base_image}"|wc -l)"
  for img in $(print_image_stack "${base_image}"); do
    [[ -f "${img}" ]] || {
      echo "   !!! WARN: ignoring non-file '${img}'"
      count=$(( count + 1 ))
      continue
    }

    local img_ro="${ro}"
    if [[ "$((count+1))" -lt "${stack_size}" ]] ; then
      img_ro="true"
    fi

    local mount_point="${image_mnt_topdir}/${count}"
    mount_fs_image "${img}" "${mount_point}" "${img_ro}"

    local img_file="$(basename "${img}")"
    stack="${img_file}:${stack}"

    local stackfile="${mount_point}/${UTIL_IMAGE_STACK_FILE}"
    if [[ "${ro}" != "true" && ! -f "${stackfile}" ]] ; then
      echo "  Image stack info '${stackfile}' not found, adding."
      echo -e "${stack//:/\\n}" >  "${stackfile}"
    fi

    count=$(( count + 1 ))

    if [[ "${deep}" == "true" && "${count}" -gt 1 ]] ; then
      mount_overlay "${image_mnt_topdir}" "${mount_point}" "${ro}"
    fi
  done

  # Only mount overlays if there are any snapshots, i.e. if there's a need to merge
  if [[ "${count}" -gt 1 && "${deep}" != "true" ]] ; then
    mount_overlay "${image_mnt_topdir}" "${mount_point}" "${ro}"
  fi
}
# --

function umount_image_stack() {
  local image_mnt_topdir="${1}"

  local mount_point
  for mount_point in $(print_mount_stack "${image_mnt_topdir}" "true"); do
    [[ -d "${mount_point}" ]] || continue
    local ovl_mnt="${mount_point}/${UTIL_IMAGE_MERGEDIR}"
    umount_sync "${ovl_mnt}"
    umount_sync "${mount_point}"
    rmdir "${mount_point}"
  done
}
# --

function cb_cleanup()     { true; }

function cleanup() {
  local image_mnt_topdir="${1}"
  local netfs_mount="${2:-}"
  local images_storage_dir="${3:-}"

  announce "Cleaning up"

  set +e

  if [[ -d "${image_mnt_topdir}" ]] ; then
    umount_image_stack "${image_mnt_topdir}"
    rmdir "${image_mnt_topdir}"
  fi

  local wip_dir="${images_storage_dir}/${UTIL_IMAGE_WIP_SUBDIR}"
  if [[ -n "${images_storage_dir}" && -d "${wip_dir}" ]] ; then
    echo "  Removing incomplete / WIP image dir '${wip_dir}'"
    rm -vrf "${wip_dir}"
  fi

  if [[ -n "${netfs_mount}" ]] ; then
    umount_netfs "${netfs_mount}"
  fi

  cb_cleanup

  set -e

  echo "All done."
}
# --

function init_trap() {
  local image_mnt_topdir="${1}"
  local netfs_mount="${2:-}"
  local images_storage_dir="${3:-}"

  if ! netfs_needs_mounting "${netfs_mount}"; then
    netfs_mount=""
  fi
  trap "cleanup '${image_mnt_topdir}' '${netfs_mount}' '${images_storage_dir}'" EXIT
}
# --
