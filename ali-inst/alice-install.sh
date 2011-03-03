#!/bin/bash

#
# alice-install -- by Dario Berzano <dario.berzano@to.infn.it>
#
# Installs all the ALICE software on Ubuntu/Mac hopefully without any human
# intervention.
#

#
# Variables
#

export SWALLOW_LOG="/tmp/$USER-build-alice"
export ERR="$SWALLOW_LOG.err"
export OUT="$SWALLOW_LOG.out"
export ENVSCRIPT=""

#
# Functions
#

# Returns date in current timezone in a compact format
function DateTime() {
  date +%Y%m%d-%H%M%S
}

# Prints the time given in seconds in hours, minutes, seconds
function NiceTime() {
  local SS HH MM STR
  SS="$1"

  let "HH=SS / 3600"
  let "SS=SS % 3600"
  [ $HH -gt 0 ] && STR=" ${HH}h"

  let "MM=SS / 60"
  let "SS=SS % 60"
  [ $MM -gt 0 ] && STR="${STR} ${MM}m"

  [ $SS -gt 0 ] && STR="${STR} ${SS}s"
  [ "$STR" == "" ] && STR="0s"

  echo $STR

  #printf "%02dh %02dm %02ds" $HH $MM $SS
}

# Prints the command name when it is started.
#  - $1: command description
function SwallowStart() {
  local MSG OP CMD

  OP="$1"
  CMD="$2"

  MSG='*** ['"$(DateTime)"'] BEGIN CWD='"$PWD"' CMD='"$CMD"' ***'
  echo -e "$MSG" >> "$OUT"
  echo -e "$MSG" >> "$ERR"

  echo -en "[....] $OP..."

}

# Prints command's progress with percentage and time.
#  - $1: command description
#  - $2: current percentage
#  - $3: start timestamp (seconds)
function SwallowStep() {
  local TS_START OP MSG PCT PCT_FMT

  OP="$1"
  PCT=$2
  TS_START=${3}

  let TS_DELTA=$(date +%s)-TS_START

  # Prints progress
  echo -ne '\r                                                  \r'
  PCT_FMT=$( printf "%3d%%" $PCT )
  echo -ne "[\033[1;34m$PCT_FMT\033[m] $OP \033[1;36m$(NiceTime $TS_DELTA)\033[m"

  return $RET

}

# Prints the command with its exit status (OK or FAILED) and time taken.
#  - $1: command description
#  - $2: the exit code of command
#  - $3: start timestamp (seconds) (optional)
#  - $4: end timestamp (seconds) (optional)
function SwallowEnd() {

  local TS_END TS_START OP MSG RET

  OP="$1"
  RET=$2
  TS_START=${3-0}  # defaults to 0
  TS_END=${4-0}

  let TS_DELTA=TS_END-TS_START

  # Prints success (green OK) or fail (red FAIL)
  echo -ne '\r'
  [ $RET == 0 ] && \
    echo -ne '[ \033[1;32mOK\033[m ]' || echo -ne '[\033[1;31mFAIL\033[m]'
  echo -ne " ${OP}"

  # Prints time only if greater than 1 second
  if [ $TS_DELTA -gt 1 ]; then
    echo -e " \033[1;36m$(NiceTime $TS_DELTA)\033[m"
  else
    echo "   "
  fi

  # On the log files (out, err)
  MSG='*** ['"$(DateTime)"'] END CWD='"$PWD"' ERR='"$RET"' CMD='"$@"' ***'
  echo -e "$MSG" >> "$OUT"
  echo -e "$MSG" >> "$ERR"

  return $RET
}

# Sends everything to a logfile
function Swallow() {

  local MSG RET TSSTART TSEND DELTAT FATAL OP

  # Abort on errors?
  if [ "$1" == "-f" ]; then
    FATAL=1
    shift
  else
    FATAL=0
  fi

  OP="$1"
  shift

  SwallowStart "$OP" "$@"
  TSSTART=$(date +%s)

  "$@" >> "$OUT" 2>> "$ERR"
  RET=$?

  TSEND=$(date +%s)
  SwallowEnd "$OP" $RET $TSSTART $TSEND

  if [ $RET != 0 ] && [ $FATAL == 1 ]; then
    LastLogLines -e
    exit 1
  fi

  return $RET
}

# Prints the last lines of both log files
function LastLogLines() {
  local LASTLINES=20
  local ISERROR=0

  if [ "$1" == "-e" ]; then
    echo ""
    echo -e "\033[1;41m\033[1;37m!!! Operation $1 ended with errors !!!\033[m"
  fi

  echo ""
  echo -e "\033[1;33m=== Last $LASTLINES lines of stdout -- $SWALLOW_LOG.out ===\033[m"
  tail -n$LASTLINES "$SWALLOW_LOG".out
  echo ""
  echo -e "\033[1;33m=== Last $LASTLINES lines of stderr -- $SWALLOW_LOG.err ===\033[m"
  tail -n$LASTLINES "$SWALLOW_LOG".err
  echo ""
}

# Echoes a colored banner
function Banner() {
  echo -e '\033[1;33m'"$1"'\033[m'
}

# Module to fetch and compile ROOT
function ModuleRoot() {
  Banner "Compiling ROOT..."
  Swallow -f "Sourcing envvars" source "$ENVSCRIPT" -n

  if [ ! -d "$ROOTSYS" ]; then
    Swallow -f "Creating ROOT directory" mkdir -p "$ROOTSYS"
  fi

  Swallow -f "Moving into ROOT directory" cd "$ROOTSYS"

  if [ ! -e $ROOTSYS/configure ]; then
    [ $ROOT_VER == "trunk" ] && \
      CMD="svn co https://root.cern.ch/svn/root/trunk ." || \
      CMD="svn co https://root.cern.ch/svn/root/tags/$ROOT_VER ."
    Swallow -f "Downloading ROOT $ROOT_VER" $CMD
  fi

  Swallow -f "Configuring ROOT" ./configure \
    --with-pythia6-uscore=SINGLE \
    --with-alien-incdir="$GSHELL_ROOT/include" \
    --with-alien-libdir="$GSHELL_ROOT/lib" \
    --with-xrootd="$GSHELL_ROOT" \
    --with-f77=gfortran \
    --enable-minuit2 \
    --enable-roofit \
    --enable-soversion
  Swallow -f "Building ROOT" make -j$MJ
}

# Module to fetch and compile Geant3
function ModuleGeant3() {
  Banner "Compiling Geant3..."
  Swallow -f "Sourcing envvars" source "$ENVSCRIPT" -n

  if [ ! -d "$GEANT3DIR" ]; then
    Swallow -f "Creating Geant3 directory" mkdir -p "$GEANT3DIR"
  fi

  Swallow -f "Moving into Geant3 directory" cd "$GEANT3DIR"

  if [ ! -e make ]; then
    [ $G3_VER == "trunk" ] && \
      CMD="svn co https://root.cern.ch/svn/geant3/trunk ." || \
      CMD="svn co https://root.cern.ch/svn/geant3/tags/$G3_VER ."
    Swallow -f "Downloading Geant3 $G3_VER" $CMD
  fi

  Swallow -f "Building Geant3" make
}

# Module to fetch, update and compile AliRoot
function ModuleAliRoot() {
  Banner "Compiling AliRoot..."
  Swallow -f "Sourcing envvars" source "$ENVSCRIPT" -n

  if [ ! -d "$ALICE_ROOT" ]; then
    Swallow -f "Creating AliRoot source directory" mkdir -p "$ALICE_ROOT"
  fi

  if [ ! -d "$ALICE_BUILD" ]; then
    Swallow -f "Creating AliRoot build directory" mkdir -p "$ALICE_BUILD"
  fi

  Swallow -f "Moving into AliRoot source directory" cd "$ALICE_ROOT"

  if [ ! -d "STEER" ]; then
    [ "$ALICE_VER" == "trunk" ] && \
      CMD="svn co https://alisoft.cern.ch/AliRoot/trunk ." || \
      CMD="svn co https://alisoft.cern.ch/AliRoot/tags/$ALICE_VER ."
    Swallow -f "Downloading AliRoot $ALICE_VER" $CMD
  fi

  Swallow -f "Updating AliRoot" svn up
  Swallow -f "Moving into AliRoot build directory" cd "$ALICE_BUILD"

  if [ ! -e "Makefile" ]; then
    Swallow -f "Bootstrapping AliRoot build with cmake" cmake "$ALICE_ROOT"
  fi

  SwallowProgress -f "Building AliRoot" make -j$MJ

  Swallow -f "Symlinking AliRoot include directory" \
    ln -nfs "$ALICE_BUILD"/include "$ALICE_ROOT"/include

  Swallow -f "Sourcing envvars" source "$ENVSCRIPT" -n
  Swallow -f "Testing ROOT with AliRoot libraries" \
    root -l -q "$ALICE_ROOT"/macros/loadlibs.C

}

# Cmake progress
function SwallowProgress() {

  local BGPID PCT PCT_FMT OP FATAL

  # Abort on error?
  if [ "$1" == "-f" ]; then
    FATAL=1
    shift
  else
    FATAL=0
  fi

  OP="$1"
  shift

  SwallowStart "$OP" "$@"
  TSSTART=$(date +%s)

  #( $@ > "$SWALLOW_LOG".out 2> "$SWALLOW_LOG".err ) &
  "$@" >> "$OUT" 2>> "$ERR" &
  BGPID=$!

  while ps|grep -v grep|grep $BGPID > /dev/null 2>&1
  do

    # Parse current percentage
    PCT=$( grep --text '%]' "$OUT" | \
      perl -ne '/\[\s*([0-9]{1,3})%\]/; print "$1\n"' | tail -n1 )

    # Show progress
    SwallowStep "$OP" "$PCT" $TSSTART

    # Sleep
    sleep 1

  done

  # It has finished: check exitcode
  wait $BGPID
  RET=$?

  TSEND=$(date +%s)
  SwallowEnd "$OP" $RET $TSSTART $TSEND

  if [ $RET != 0 ] && [ $FATAL == 1 ]; then
    LastLogLines -e
    exit 1
  fi

}

# Download URL $1 to file $2 using wget or curl
function Dl() {
  which curl > /dev/null 2>&1
  if [ $? == 0 ]; then
    curl -o "$2" "$1"
    return $?
  else
    wget -O "$2" "$1"
    return $?
  fi
}

# Install AliEn
function ModuleAliEn() {
  local ALIEN_INSTALLER="/tmp/alien-installer-$USER"
  Banner "Installing AliEn..."
  Swallow -f "Sourcing envvars" source "$ENVSCRIPT" -n
  Swallow -f "Downloading AliEn installer" \
    Dl http://alien.cern.ch/alien-installer "$ALIEN_INSTALLER"
  Swallow -f "Making AliEn installer executable" \
    chmod +x "$ALIEN_INSTALLER"
  Swallow -f "Installing AliEn" \
    "$ALIEN_INSTALLER" -install-dir "$ALIEN_DIR" -batch -notorrent
  rm -f "$ALIEN_INSTALLER"
}

# Module to create prefix directory
function ModulePrepare() {
  local TF
  Banner "Creating directory structure..."
  Swallow -f "Sourcing envvars" source "$ENVSCRIPT" -n

  mkdir -p "$ALICE_PREFIX" 2> /dev/null

  if [ "$USER" == "root" ]; then
    Swallow -f "Creating ALICE software directory" [ -d "$ALICE_PREFIX" ]
    Swallow -f "Opening permissions of ALICE directory" \
      chmod 0777 "$ALICE_PREFIX"
    #Swallow -f ""
  else
    TF="$ALICE_PREFIX/dummy_$RANDOM"
    touch "$TF" 2> /dev/null
    if [ $? != 0 ]; then
      Fatal "Not enough permissions: please run \"sudo $0 --structure\""
    fi
    rm "$TF"
  fi

}

# Fatal error
function Fatal() {
  echo -e "\033[1;31m$1\033[m"
  exit 1
}

# Remove old logs
function RemoveLogs() {
  rm -f "$SWALLOW_LOG".out "$SWALLOW_LOG".err
}

# Main function
function Main() {

  local DO_ROOT DOALIROOT DO_GEANT3 DO_ALIEN DO_STHG
  DO_ROOT=0
  DO_ALIROOT=0
  DO_GEANT3=0
  DO_STRUCT=0
  DO_ALIEN=0
  DO_STHG=0

  ENVSCRIPT="$PWD/alice-env.sh"
  if [ ! -r "$ENVSCRIPT" ]; then
    Fatal "Can't read file alice-env.sh in current directory"
  fi

  while [ $# -gt 0 ]; do
    case "$1" in
      --prepare) DO_STRUCT=1 ;;
      --root) DO_ROOT=1 ;;
      --geant3) DO_GEANT3=1 ;;
      --aliroot) DO_ALIROOT=1 ;;
      --alien) DO_ALIEN=1 ;;
      --all) DO_ALIEN=1 ; DO_STRUCT=1 ; DO_ROOT=1 ; DO_GEANT3=1 ; DO_ALIROOT=1 ;;
      *) echo -e "Unknown parameter: \033[1;36m$1\033[m" ; exit 1 ;;
    esac
    shift
  done

  let "DO_STHG=DO_ALIEN+DO_ROOT+DO_GEANT3+DO_ALIROOT+DO_STRUCT+DO_ALIEN"

  if [ $DO_STHG == 0 ]; then
    echo ""
    echo "Usage:"
    echo ""
    echo -e "  To build everything:           \033[1;33m$0 --all\033[m"
    echo -e "  To create directory structure: \033[1;33m[sudo] $0 --prepare\033[m"
    echo -e "  To build only something:       \033[1;33m$0 [--root] [--geant3] [--aliroot] [--alien]\033[m"
    echo ""
  fi

  RemoveLogs

  if [ $DO_STRUCT == 1 ]; then
    ModulePrepare
    let "DO_STHG--"
  fi

  if [ "$USER" == "root" ] && [ $DO_STHG -gt 0 ]; then
    Fatal "I'm refusing to continue the installation as root user"
  fi

  [ $DO_ALIEN == 1 ]   && ModuleAliEn
  [ $DO_ROOT == 1 ]    && ModuleRoot
  [ $DO_GEANT3 == 1 ]  && ModuleGeant3
  [ $DO_ALIROOT == 1 ] && ModuleAliRoot

  RemoveLogs

}

Main "$@"
