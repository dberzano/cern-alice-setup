#!/bin/bash -ex
[[ $(whoami) == root ]]
SRC="$(dirname "$0")"/bin_cvmfs
DST=/cvmfs/alice.cern.ch/bin
if mount | grep "on $DST" | grep -q bind; then
  umount "$DST"
else
  mount --bind "$SRC" "$DST"
  rm -f "$SRC/DEVEL_DIR"
  touch "$SRC/DEVEL_DIR"
  [[ -e "$DST/DEVEL_DIR" ]]
fi
echo All OK
