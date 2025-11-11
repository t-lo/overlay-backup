#!/bin/bash
# vim: ts=2 et sw=2
#
# Example callbacks for backup.sh

cb_pre_backup() {
  local name="$1"; shift
  local base="$1"; shift
  local current="$1"; shift
  local dest_dir="$1"; shift

  shift # "--"

  # "${@}" is now the backup.sh command line part after "--",
  # i.e. the list of files and directories to back up.

  if [[ "${base}" == "${current}" ]] ; then
    echo "I'm a full backup '${base}'!"
  else
    echo "I'm an incremental snapshot '${current}' based on '${base}'!"
  fi

}
# --

cb_post_backup() {
  local name="$1"
  local base="$2"
  local image="$3"
  local dest_dir="$4"

  true
}
# --

cb_cleanup() {
  # Cleanup does not get any parameters
}
# --
