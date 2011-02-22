#!/bin/bash

# Choose momentums, space separated (AliGenBox)
export MOMENTUMS="15"

# Choose OCDBs
export CDBS="fulleff 50pct-maxcorr 75pct-maxcorr r-maxcorr"

# Custom AliRoot?
#export ALICE_ROOT="/dalice07/lopez/ALICE/AliRoot/TRUNK"

# Script dir
export SCRIPTDIR=$(dirname "$0")

# Count
export CNT=0

# For each momentum...
for P in $MOMENTUMS
do

  for C in $CDBS
  do

    # Write options in Config.C
    "$SCRIPTDIR"/preprocess.sh Config.C.in \
      MUONS_PER_EVENT   2  \
      MOMENTUM_GEV_C   $P. \
      PHI_MIN_DEG       0. \
      PHI_MAX_DEG     360. \
      THETA_MIN_DEG   170. \
      THETA_MAX_DEG   180. \
      THNSPARSE_SRC   /dalice07/lopez/ALICE/GEN/pp7_MB_Gen_New.root \
    > Config.C

    # Launch the jobs (30 000 generated muons total!)
    [ $CNT -gt 0 ] && echo ""
    let CNT++
    "$SCRIPTDIR"/joblaunch.sh \
      --jobs   1 \
      --events 1 \
      --tag    testme-${C} \
      --cdb    'local:///dalice05/berzano/cdb/'${C}'/'
    #"$SCRIPTDIR"/joblaunch.sh \
    #  --jobs     30 \
    #  --events 1000 \
    #  --tag    sim-real-2mu-${C} \
    #  --cdb    'local:///dalice05/berzano/cdb/'${C}'/'

    # Remove the Config.C (it can be found in jobs directories)
    rm Config.C

  done

done