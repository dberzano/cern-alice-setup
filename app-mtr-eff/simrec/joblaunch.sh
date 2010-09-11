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

# Name of the script to view the status of the launched jobs
export JOBSSTATSCRIPT="jobstatall.sh"

# Interesting files to copy
export FILES_TO_COPY="galice.root AliESDs.root Kinematics.root TrackRefs.root $MISC_LOG sim.log rec.log misc.log"

# Temporary directory, local for the worker node
export TMP_WN_PREFIX="/users_local1/berzano"

# Log file for miscellaneous things that do not fit into sim or rec
export MISC_LOG="misc.log"

# AliRoot environment -- variables are exported only if they are not yet set
export ALIPREFIX="/dalice05/berzano/alisw"
[ "$ALICE_ROOT" == "" ] && export ALICE_ROOT="$ALIPREFIX/alice/trunk"
[ "$ROOTSYS"    == "" ] && export ROOTSYS="$ALIPREFIX/root/v5-26-00b"
[ "$G3SYS"      == "" ] && export G3SYS="$ALIPREFIX/alice/geant3-versions/v1-11"

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

  # If output directory already exists, abort job launch
  if [ -e "$OUTPREFIX" ]; then
    echo "----> Output directory already exists: $OUTPREFIX"
    echo "Aborting to avoid data loss"
    exit 3
  fi

  # Summary
  echo "==== Summary of jobs to launch ===="
  echo "---> ROOT:                     $ROOTSYS"
  echo "---> Geant3:                   $G3SYS"
  echo "---> AliRoot:                  $ALICE_ROOT"
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

  # Create the scripts that kill/stat the created jobs
  echo "#!/bin/sh" > "$OUTPREFIX/$JOBSDELSCRIPT"
  echo "#!/bin/sh" > "$OUTPREFIX/$JOBSSTATSCRIPT"
  chmod +x "$OUTPREFIX/$JOBSDELSCRIPT" "$OUTPREFIX/$JOBSSTATSCRIPT"

  # For stat: loop
  echo -n "watch -n2 'qstat" >> "$OUTPREFIX/$JOBSSTATSCRIPT"

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
export LD_LIBRARY_PATH="\$ALICE_ROOT/lib/tgt_\$ARCH:$G3SYS/lib/tgt_\$ARCH:\$ROOTSYS/lib:\$LD_LIBRARY_PATH"

cd "$OUTPREFIX/$JOBSUBDIR"

# Copy everything to a temporary directory on each worker
mkdir -p "$TMP_WN_PREFIX"
T=\$(mktemp -d "$TMP_WN_PREFIX/jobtmp_XXXXX")
cp * .* \$T/ 2> /dev/null
cd \$T/

echo "" > $MISC_LOG
echo "==== Environment ====" >> $MISC_LOG
env >> $MISC_LOG

echo "" >> $MISC_LOG
echo "==== Output of df and last lines of dmesg BEFORE jobs ====" >> $MISC_LOG
df >> $MISC_LOG
dmesg | tail -n20 >> $MISC_LOG

echo "" >> $MISC_LOG
echo "==== AliRoot steer for Sim and Rec (see sim.log, rec.log) ====" >> $MISC_LOG
aliroot -b -q $MACRO --run $RUN --events $NEVTS $EXTRAOPTS >> $MISC_LOG 2>&1

echo "" >> $MISC_LOG
echo "==== Output of df and last lines of dmesg AFTER jobs ====" >> $MISC_LOG
df >> $MISC_LOG
dmesg | tail -n20 >> $MISC_LOG

# Copy only desired files on destdir
for F in $FILES_TO_COPY
do
  cp \$F "$OUTPREFIX/$JOBSUBDIR/\$F" >> $MISC_LOG 2>&1
done

# Remove temporary garbage on the WN
cd /
rm -rf \$T

# Archive macros
cd "$OUTPREFIX/$JOBSUBDIR"
tar cjf exec.tar.bz2 $MACRO $DEPS $TAG.sh
rm -f $MACRO $DEPS $TAG.sh

# Archive logs
bzip2 -9 misc.log
bzip2 -9 sim.log
bzip2 -9 rec.log

EOF
    chmod +x "$OUTPREFIX/$JOBSUBDIR/$TAG.sh"

    # Launch the job
    mkdir -p "$OUTPREFIX/outputs"
    JOBID=`cd "$OUTPREFIX/outputs" ; qsub $OUTPREFIX/$JOBSUBDIR/$TAG.sh`

    # Add in the list of jobs to kill (or stat)
    echo "qdel $JOBID" >> "$OUTPREFIX/$JOBSDELSCRIPT"
    echo -n " $JOBID" >> "$OUTPREFIX/$JOBSSTATSCRIPT"

    # Increment run number
    let RUN++
  done

  # End loop in stat script
  echo "'" >> "$OUTPREFIX/$JOBSSTATSCRIPT"

  # List contents of job dir
  echo ""
  echo "==== Contents of $OUTPREFIX ===="
  ls -l "$OUTPREFIX"

  # How to kill all jobs
  echo ""
  echo "==== How to kill all the just launched jobs ===="
  echo "---> $OUTPREFIX/$JOBSDELSCRIPT"

  # How to stat all jobs
  echo ""
  echo "==== How to view the status of all the just launched jobs ===="
  echo "---> $OUTPREFIX/$JOBSSTATSCRIPT"
}

#
# Entry point
#

Main "$@"
