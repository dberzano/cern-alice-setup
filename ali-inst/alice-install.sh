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

# Sends everything to a logfile
function Swallow() {

  local ERR="$SWALLOW_LOG.err"
  local OUT="$SWALLOW_LOG.out"
  local MSG RET TSSTART TSEND DELTAT
  local OP="$1"
  shift

  MSG='\n*** ['"$(DateTime)"'] BEGIN CWD='"$PWD"' CMD='"$@"' ***\n'
  echo -e "$MSG" >> "$OUT"
  echo -e "$MSG" >> "$ERR"

  echo -en "[....] $OP..."
  TSSTART=$(date +%s)
  "$@" >> "$OUT" 2>> "$ERR"
  RET=$?
  TSEND=$(date +%s)

  let DELTAT=TSEND-TSSTART

  echo -ne '\r'
  [ $RET == 0 ] && \
    echo -en '[ \033[1;32mOK\033[m ]' || echo -en '[\033[1;31mFAIL\033[m]'
  echo -e " $OP \033[1;36m$(NiceTime $DELTAT)\033[m"

  MSG='\n*** ['"$(DateTime)"'] END CWD='"$PWD"' ERR='"$RET"' CMD='"$@"' ***\n'
  echo -e "$MSG" >> "$OUT"
  echo -e "$MSG" >> "$ERR"

  return $RET
}

# Like Swallow, but terminates on fatal error
function SwallowFatal() {
  local LASTLINES=20
  Swallow "$@"
  if [ $? != 0 ]; then
    echo ""
    echo -e "\033[1;41m\033[1;37m!!! Operation $1 ended with errors !!!\033[m"
    echo ""
    echo -e "\033[1;33m=== Last $LASTLINES lines of stdout -- $SWALLOW_LOG.out ===\033[m"
    tail -n$LASTLINES "$SWALLOW_LOG".out
    echo ""
    echo -e "\033[1;33m=== Last $LASTLINES lines of stderr -- $SWALLOW_LOG.err ===\033[m"
    tail -n$LASTLINES "$SWALLOW_LOG".err
    echo ""
    exit 1
  fi
}

# Echoes a colored banner
function Banner() {
  echo -e '\033[1;33m'"$1"'\033[m'
}

# Module to fetch and compile ROOT
function ModuleRoot() {
  Banner "Compiling ROOT..."
  SwallowFatal "Sourcing envvars" source "$ENVSCRIPT" -n

  if [ -d "$ROOTSYS" ]; then
    SwallowFatal "Creating ROOT directory" mkdir -p "$ROOTSYS"
  fi

  SwallowFatal "Moving into ROOT directory" cd "$ROOTSYS"

  if [ ! -e $ROOTSYS/configure ]; then
    [ $ROOT_VER == "trunk" ] && \
      CMD="svn co https://root.cern.ch/svn/root/trunk ." || \
      CMD="svn co https://root.cern.ch/svn/root/tags/$ROOT_VER ."
    SwallowFatal "Downloading ROOT $ROOT_VER" $CMD
  fi

  SwallowFatal "Configuring ROOT" ./configure \
    --with-pythia6-uscore=SINGLE \
    --with-alien-incdir="$GSHELL_ROOT/include" \
    --with-alien-libdir="$GSHELL_ROOT/lib" \
    --with-xrootd="$GSHELL_ROOT" \
    --with-f77=gfortran \
    --enable-minuit2 \
    --enable-roofit \
    --enable-soversion
  SwallowFatal "Building ROOT" make -j$MJ
}

# Module to fetch and compile Geant3
function ModuleGeant3() {
  Banner "Compiling Geant3..."
  SwallowFatal "Sourcing envvars" source "$ENVSCRIPT" -n

  if [ ! -d "$GEANT3DIR" ]; then
    SwallowFatal "Creating Geant3 directory" mkdir -p "$GEANT3DIR"
  fi

  SwallowFatal "Moving into Geant3 directory" cd "$GEANT3DIR"
  SwallowFatal "Building Geant3" make
}

# Module to fetch, update and compile AliRoot
function ModuleAliRoot() {
  Banner "Compiling AliRoot..."
  SwallowFatal "Sourcing envvars" source "$ENVSCRIPT" -n

  if [ ! -d "$ALICE_ROOT" ]; then
    SwallowFatal "Creating AliRoot source directory" mkdir -p "$ALICE_ROOT"
  fi

  if [ ! -d "$ALICE_INSTALL" ]; then
    SwallowFatal "Creating AliRoot build directory" mkdir -p "$ALICE_INSTALL"
  fi

  SwallowFatal "Moving into AliRoot source directory" cd "$ALICE_ROOT"

  if [ ! -d "STEER" ]; then
    [ "$ALICE_VER" == "trunk" ] && \
      CMD="svn co https://alisoft.cern.ch/AliRoot/trunk ." || \
      CMD="svn co https://alisoft.cern.ch/AliRoot/tags/$ALICE_VER ."
    SwallowFatal "Downloading AliRoot $ALICE_VER" $CMD
  fi

  SwallowFatal "Updating AliRoot" svn up
  SwallowFatal "Moving into AliRoot build directory" cd "$ALICE_INSTALL"

  if [ ! -e "Makefile" ]; then
    SwallowFatal "Bootstrapping AliRoot build with cmake" cmake "$ALICE_ROOT"
  fi

  SwallowFatal "Building AliRoot" make -j$MJ

  SwallowFatal "Symlinking AliRoot include directory" \
    ln -nfs "$ALICE_INSTALL"/include "$ALICE_ROOT"/include

  SwallowFatal "Sourcing envvars" source "$ENVSCRIPT" -n
  SwallowFatal "Testing ROOT with AliRoot libraries" \
    root -l -q "$ALICE_ROOT"/macros/loadlibs.C

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
  SwallowFatal "Sourcing envvars" source "$ENVSCRIPT" -n
  SwallowFatal "Downloading AliEn installer" \
    Dl http://alien.cern.ch/alien-installer "$ALIEN_INSTALLER"
  SwallowFatal "Making AliEn installer executable" \
    chmod +x "$ALIEN_INSTALLER"
  SwallowFatal "Installing AliEn" \
    "$ALIEN_INSTALLER" -install-dir "$ALIEN_DIR" -batch -notorrent
  rm -f "$ALIEN_INSTALLER"
}

# Module to create prefix directory
function ModulePrepare() {
  local TF
  Banner "Creating directory structure..."
  SwallowFatal "Sourcing envvars" source "$ENVSCRIPT" -n

  mkdir -p "$ALICE_PREFIX" 2> /dev/null

  if [ "$USER" == "root" ]; then
    SwallowFatal "Creating ALICE software directory" [ -d "$ALICE_PREFIX" ]
    SwallowFatal "Opening permissions of ALICE directory" \
      chmod 0777 "$ALICE_PREFIX"
    #SwallowFatal ""
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
      --all) DO_STRUCT=1 ; DO_ROOT=1 ; DO_GEANT3=1 ; DO_ALIROOT=1 ;;
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
