#!/bin/bash -e
THISDIR=$(pwd)
DEST=/cvmfs/alice-test.cern.ch/bin

DIRS=( /cvmfs/alice-test.cern.ch/bin $PWD
       /cvmfs/alice.cern.ch/bin      $PWD
       /cvmfs/alice-test.cern.ch/el5-x86_64/Modules/modulefiles/AliEn-Runtime AliEn-Runtime
       /cvmfs/alice-test.cern.ch/el7-x86_64/Modules/modulefiles/GCC-Toolchain GCC-Toolchain
       /cvmfs/alice-test.cern.ch/etc/toolchain/modulefiles toolchain )

for ((I=0; I<${#DIRS[@]}; I+=2)); do
  umount -f ${DIRS[$I]} || true
done
[[ $1 == --umount || $1 == -u ]] && { echo all umounted, exiting; exit 1; }
for ((I=0; I<${#DIRS[@]}; I+=2)); do
  mount --bind ${DIRS[$((I+1))]} ${DIRS[$I]}
done
echo all ok
