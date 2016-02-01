#!/bin/bash -ex
PROG=$(cd $(dirname $0); pwd)/$(basename $0)
source /cvmfs/alice.cern.ch/etc/login.sh
export ALIENV_DEBUG=1
alienv q

if [[ ! -e /.dockerenv ]]; then
  # Run self inside a Docker container.
  printf "\n\n\n=== NOW RUNNING INSIDE A CONTAINER ===\n\n\n"
  docker run -it --rm \
             -v /cvmfs:/cvmfs \
             -v $PROG:/enter.sh \
             alisw/slc6-builder \
             /enter.sh
fi
