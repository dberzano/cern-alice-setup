#
# simrec.sh -- by Dario Berzano <dario.berzano@gmail.com>
#
# Script used to launch simrec.C either locally or with qsub. In either case the
# local directory is not filled with files, but everything is run in a separated
# environment.
#

#
# Variables
#

# Script
export MACRO="simrec.C"
export DEPS="sim.C rec.C Config.C"
export VDATE=`date +%Y%m%d-%H%M%S`
export PREFIX
export JOBS=0
export FIRSTRUN=0
export NEVTS=100
export PREFIX=$(cd `dirname "$0"` ; pwd)
export PROGBASE=`basename $0`
export PROGPATH="$PREFIX/$PROGBASE"
export OUTPREFIX="/dalice05/berzano/jobs"
export OUTDIR=""
export EXTRAOPTS=""

# First function to be called
function Main() {

  local ERR=0

  # Parse arguments
  while [ $# -gt 0 ]; do
    case "$1" in
      --jobs)     JOBS=$2 ;;
      --firstrun) FIRSTRUN=$2 ;;
      --events)   NEVTS=$2 ;;
      --out)      OUTDIR=$2 ;;
      --prefix)   PREFIX=$2 ;;
      *)          EXTRAOPTS="$EXTRAOPTS $1" ;;
    esac
    shift
  done

  if [ "$NEVTS" -lt 1 ]; then
    echo "Specify # events with --events <n>"
    exit 1
  fi

  AliEnv

  if [ "$JOBS" -gt 0 ]; then
    RunBatch
  else
    RunLocal
  fi
  
}

# Environment for AliRoot & co.
function AliEnv() {

  #export ALIPREFIX="/opt/alice/"
  #export ALICE_ROOT="$ALIPREFIX/alice/trunk0"
  #export ROOTSYS="$ALIPREFIX/root/v5-26-00b"
  #export PATH="$ALIPREFIX/alice/trunk0/bin/tgt_macosx64:$ALIPREFIX/root/v5-26-00b/bin:$PATH"
  #export LD_LIBRARY_PATH="$ALIPREFIX/alice/trunk0/lib/tgt_macosx64:$ALIPREFIX/alice/geant3-versions/v1-11/lib/tgt_macosx64:$ROOTSYS/lib:$LD_LIBRARY_PATH"

  export ALIPREFIX="/dalice05/berzano/alisw"
  export ALICE_ROOT="$ALIPREFIX/alice/trunk"
  export ROOTSYS="$ALIPREFIX/root/v5-26-00b"
  export PATH="$ALIPREFIX/alice/trunk/bin/tgt_linux:$ALIPREFIX/root/v5-26-00b/bin:$PATH"
  export LD_LIBRARY_PATH="$ALIPREFIX/alice/trunk/lib/tgt_linux:$ALIPREFIX/alice/geant3-versions/v1-11/lib/tgt_linux:$ROOTSYS/lib:$LD_LIBRARY_PATH"

}

# Run locally
function RunLocal() {
  local RUN=$FIRSTRUN
  local OUT

  if [ "$OUTDIR" != "" ]; then
    # Custom directory (--out)
    OUT="$OUTDIR"
  else
    # Standard output prefix
    OUT="$OUTPREFIX/test-$VDATE"
  fi

  RunOnce $RUN "$OUT"
}

# Run on batch farm
function RunBatch() {

  local RUN
  local MAXRUN
  local OUT="$OUTPREFIX/batch-$VDATE"
  local SINGLEOUT
  local JOBEXEC

  echo "Output directory: $OUT"

  let MAXRUN=FIRSTRUN+JOBS

  mkdir -p "$OUT/qlog"
  cd "$OUT/qlog"

  for ((RUN=$FIRSTRUN; $RUN < $MAXRUN; RUN++)); do
    SINGLEOUT="$OUT/`printf %06d $RUN`"
    mkdir -p "$SINGLEOUT"
    cp "$PROGPATH" "$SINGLEOUT/"
    JOBEXEC="$SINGLEOUT/launch.sh"
    cat > "$JOBEXEC" <<EOF 
#!/bin/bash
cd "$SINGLEOUT"
./$PROGBASE --firstrun $RUN --events $NEVTS --out "$SINGLEOUT" --prefix "$PREFIX" $EXTRAOPTS > stdout 2> stderr
EOF
    chmod +x "$JOBEXEC"
    qsub "$JOBEXEC"
  done
}

# Run once
function RunOnce() {

  local RUN=$1
  local OUT="$2"

  echo "====== STARTING JOB ======"
  echo "Working dir: $OUT"

  # Create directory
  mkdir -p "$OUT"
  if [ $? != 0 ]; then
    echo "Cannot create output directory $OUT, check permissions"
    exit 3
  fi

  cd "$PREFIX"
  cp $DEPS $MACRO "$ALICE_ROOT/.rootrc" "$OUT/"

  cd "$OUT"
  aliroot -b -q $MACRO --run $RUN --events $NEVTS $EXTRAOPTS
}

#
# Entry point
#

Main "$@"
