#!/bin/bash

# Params
export MOMENTUMS="10 15 20"
export CDBS="fulleff reff"

# For each momentum...
for P in $MOMENTUMS
do

  for C in $CDBS
  do

    # Write options in Config.C
    ./preprocess.sh Config.C.in \
      MUONS_PER_EVENT  1 \
      MOMENTUM_GEV_C  $P. > Config.C

    # Launch the jobs (40 000 generated muons total!)
    ./joblaunch.sh \
      --jobs     40 \
      --events 1000 \
      --tag    sim-mumin-onemu-${P}gev-${C} \
      --cdb    'local:///dalice05/berzano/cdb/'${C}'/'

    # Remove the Config.C (it can be found in jobs directories)
    rm Config.C

  done

done
