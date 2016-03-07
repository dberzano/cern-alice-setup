#!/bin/bash -e
THISDIR=$(pwd)
DEST=/cvmfs/alice.cern.ch/bin
umount -f $DEST || true
mount --bind $THISDIR $DEST
echo all ok, overriding $DEST
