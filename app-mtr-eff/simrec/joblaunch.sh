#!/bin/bash

#
# Launches jobs on LPC farm.
#
# by Dario Berzano <dario.berzano@gmail.com>
#

#
# Global variables
#

# Output prefix of the job
export OUTPREFIX="/dalice05/berzano/jobs"

# Macro that steers the job
export MACRO="simrec.C"

# Dependencies to copy into each job's folder
export DEPS="sim.C rec.C Config.C"

# Current date and time tag
export VDATE=`date +%Y%m%d-%H%M%S`

# Name of the script to kill all the jobs
export JOBSDELSCRIPT="jobsdelall.sh"

# AliRoot environment
export ALIPREFIX="/dalice05/berzano/alisw"
export ALICE_ROOT="$ALIPREFIX/alice/trunk"
export ROOTSYS="$ALIPREFIX/root/v5-26-00b"
export G3_ROOT="$ALIPREFIX/alice/geant3-versions/v1-11"

#
# Functions
#

# First function called
function Main() {

  local JOBS=0       # number of jobs
  local FIRSTRUN=0   # number of the first run
  local NEVTS=0      # events per run
  local EXTRAOPTS    # extra options directly passed to AliRoot
  local TAG          # a meaningful name for the simulation

  # Parse arguments
  while [ $# -ge 2 ]; do
    case "$1" in
      --jobs)      JOBS=$2 ;;
      --firstrun)  FIRSTRUN=$2 ;;
      --tag)       TAG=$2 ;;
      --events)    NEVTS=$2 ;;
      *)           EXTRAOPTS=`echo $EXTRAOPTS $1 $2` ;;
    esac
    shift 2
  done

  # Check if arguments are given
  local ERR=0
  if [ "$JOBS" == "0" ]; then
    echo "Specify number of jobs with --jobs <n>"
    ERR=1
  fi
  if [ "$NEVTS" == "0" ]; then
    echo "Specify number of events per job with --events <n>"
    ERR=1
  fi
  if [ $ERR == 1 ]; then
    echo "Aborting"
    return
  fi

  # If no tag given, choose a default one with current date and time
  local TAGMSG
  if [ "$TAG" == "" ]; then
    TAG="batch-$VDATE"
    TAGMSG=" <-- this is the default one: customize with --tag <name>"
  fi

  # Append tag to the default output directory
  OUTPREFIX="$OUTPREFIX/$TAG"

  # Summary
  echo "==== Summary of jobs to launch ===="
  echo "---> Number of jobs:           $JOBS"
  echo "---> Number of events per job: $NEVTS"
  echo "---> First job number:         $FIRSTRUN (--firstrun <n>)"
  echo "---> Job tag identifier:       ${TAG}${TAGMSG}"
  echo "---> Output directory:         $OUTPREFIX"
  echo "---> Extra AliRoot options:    $EXTRAOPTS"
  echo ""
  echo -n "Is this correct? Answer YES in capital case to launch the jobs: "
  local ANS
  read ANS
  if [ "$ANS" != "YES" ]; then
    echo "Aborting"
    exit 2
  fi

  # Create output directory
  mkdir -p "$OUTPREFIX"

  # Create the script that kills the created jobs
  echo "#!/bin/sh" > "$OUTPREFIX/$JOBSDELSCRIPT"
  chmod +x "$OUTPREFIX/$JOBSDELSCRIPT"

  # For each job (or run)...
  local I
  local RUN=$FIRSTRUN
  for ((I=0; $I<$JOBS; I++)); do
    JOBSUBDIR=`printf "%06d" $RUN`
    mkdir "$OUTPREFIX/$JOBSUBDIR"

    # Copy deps from current directory, and including AliRoot's rootrc
    cp $MACRO $DEPS "$ALICE_ROOT/.rootrc" "$OUTPREFIX/$JOBSUBDIR"

    # Create the launch script
    cat > "$OUTPREFIX/$JOBSUBDIR/$TAG.sh" <<EOF
#!/bin/sh
export ALICE_ROOT="$ALICE_ROOT"
export ROOTSYS="$ROOTSYS"
export ARCH=\`\$ROOTSYS/bin/root-config --arch\`
export PATH="\$ALICE_ROOT/bin/tgt_\$ARCH:$ALIPREFIX/root/v5-26-00b/bin:\$PATH"
export LD_LIBRARY_PATH="\$ALICE_ROOT/lib/tgt_\$ARCH:$G3_ROOT/lib/tgt_\$ARCH:\$ROOTSYS/lib:\$LD_LIBRARY_PATH"

cd "$OUTPREFIX/$JOBSUBDIR"

aliroot -b -q $MACRO --run $RUN --events $NEVTS $EXTRAOPTS > stdout 2> stderr
EOF
    chmod +x "$OUTPREFIX/$JOBSUBDIR/$TAG.sh"

    # Launch the job
    JOBID=`cd "$OUTPREFIX/$JOBSUBDIR" ; qsub $TAG.sh`

    # Add in the list of jobs to kill
    echo "qdel $JOBID" >> "$OUTPREFIX/$JOBSDELSCRIPT"

    # Increment run number
    let RUN++
  done

  # List contents of job dir
  echo ""
  echo "==== Contents of $OUTPREFIX ===="
  ls -l "$OUTPREFIX"

  # How to kill all jobs
  echo ""
  echo "==== How to kill all the just launched jobs ===="
  echo "---> $OUTPREFIX/$JOBSDELSCRIPT"

}

#
# Entry point
#

Main "$@"
