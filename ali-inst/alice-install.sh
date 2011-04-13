#!/bin/bash

#
# alice-install -- by Dario Berzano <dario.berzano@cern.ch>
#
# Installs all the ALICE software on Ubuntu/Mac hopefully without the least
# possible human intervention.
#

#
# Variables
#

export SWALLOW_LOG="/tmp/alice-autobuild-$USER"
export ERR="$SWALLOW_LOG.err"
export OUT="$SWALLOW_LOG.out"
export ENVSCRIPT=""
export NCORES=0

#
# Functions
#

# Sources environment variables
function SourceEnvVars() {
  local R
  source "$ENVSCRIPT" -n
  R=$?
  [ $NCORES -gt 0 ] && MJ=$NCORES
  return $R
}

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
  local MSG OP

  OP="$1"
  shift

  MSG='*** ['"$(DateTime)"'] BEGIN OP='"$OP"' CWD='"$PWD"' CMD='"$@"' ***'
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
#  - $@: the command (from $5 on)
function SwallowEnd() {

  local TS_END TS_START OP MSG RET

  OP="$1"
  RET=$2
  TS_START=${3-0}  # defaults to 0
  TS_END=${4-0}

  # After this line, $@ will contain the command
  shift 4

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
  MSG='*** ['"$(DateTime)"'] END OP='"$OP"' CWD='"$PWD"' ERR='"$RET"' CMD='"$@"' ***'
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
  SwallowEnd "$OP" $RET $TSSTART $TSEND "$@"

  if [ $RET != 0 ] && [ $FATAL == 1 ]; then
    LastLogLines -e
    exit 1
  fi

  return $RET
}

# Permanently (and silently) accepts a SVN certificate
function AcceptSvn() {
  yes p | svn info "$1" > /dev/null 2>&1
  return $?
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
  echo ""
  echo -e '\033[1;33m'"$1"'\033[m'
}

# Module to fetch and compile ROOT
function ModuleRoot() {

  local SVN_ROOT="https://root.cern.ch/svn/root"

  Banner "Compiling ROOT..."
  Swallow -f "Sourcing envvars" SourceEnvVars

  if [ ! -d "$ROOTSYS" ]; then
    Swallow -f "Creating ROOT directory" mkdir -p "$ROOTSYS"
  fi

  Swallow -f "Moving into ROOT directory" cd "$ROOTSYS"
  Swallow -f "Permanently accepting SVN certificate" AcceptSvn $SVN_ROOT

  # Different behaviors if it is trunk or not
  if [ "$ROOT_VER" == "trunk" ]; then
    # Trunk: download if needed, update to latest if already present
    if [ ! -f "configure" ]; then
      # We have to download it
      Swallow -f "Downloading ROOT trunk" svn co $SVN_ROOT/trunk .
    else
      # We just have to update it
      Swallow -f "Updating ROOT to latest trunk" svn up --non-interactive
    fi
  else
    # No trunk: just download, never update
    if [ ! -f "configure" ]; then
      Swallow -f "Downloading ROOT $ROOT_VER" svn co $SVN_ROOT/tags/$ROOT_VER .
    fi
  fi

  Swallow -f "Configuring ROOT" ./configure \
    --with-pythia6-uscore=SINGLE \
    --with-alien-incdir="$GSHELL_ROOT/include" \
    --with-alien-libdir="$GSHELL_ROOT/lib" \
    --with-xrootd="$GSHELL_ROOT" \
    --with-f77=gfortran \
    --enable-minuit2 \
    --enable-roofit \
    --enable-soversion \
    --disable-bonjour
  Swallow -f "Building ROOT" make -j$MJ
}

# Module to fetch and compile Geant3
function ModuleGeant3() {

  local SVN_G3="https://root.cern.ch/svn/geant3/"

  Banner "Compiling Geant3..."
  Swallow -f "Sourcing envvars" SourceEnvVars

  if [ ! -d "$GEANT3DIR" ]; then
    Swallow -f "Creating Geant3 directory" mkdir -p "$GEANT3DIR"
  fi

  Swallow -f "Moving into Geant3 directory" cd "$GEANT3DIR"
  Swallow -f "Permanently accepting SVN certificate" AcceptSvn $SVN_G3

  # Different behaviors if it is trunk or not
  if [ "$G3_VER" == "trunk" ]; then
    # Trunk: download if needed, update to latest if already present
    if [ ! -f "Makefile" ]; then
      # We have to download it
      Swallow -f "Downloading Geant3 trunk" svn co $SVN_G3/trunk .
    else
      # We just have to update it
      Swallow -f "Updating Geant3 to latest trunk" svn up --non-interactive
    fi
  else
    # No trunk: just download, never update
    if [ ! -f "Makefile" ]; then
      Swallow -f "Downloading Geant3 $G3_VER" svn co $SVN_G3/tags/$G3_VER .
    fi
  fi

  Swallow -f "Building Geant3" make

}

# Module to fetch, update and compile AliRoot
function ModuleAliRoot() {

  local SVN_ALIROOT="https://alisoft.cern.ch/AliRoot"

  Banner "Compiling AliRoot..."
  Swallow -f "Sourcing envvars" SourceEnvVars

  if [ ! -d "$ALICE_ROOT" ]; then
    Swallow -f "Creating AliRoot source directory" mkdir -p "$ALICE_ROOT"
  fi

  if [ ! -d "$ALICE_BUILD" ]; then
    Swallow -f "Creating AliRoot build directory" mkdir -p "$ALICE_BUILD"
  fi

  Swallow -f "Moving into AliRoot source directory" cd "$ALICE_ROOT"
  Swallow -f "Permanently accepting SVN certificate" AcceptSvn $SVN_ALIROOT

  # Different behaviors if it is trunk or not
  if [ "$ALICE_VER" == "trunk" ]; then
    # Trunk: download if needed, update to latest if already present
    if [ ! -d "STEER" ]; then
      # We have to download it
      Swallow -f "Downloading AliRoot trunk" svn co $SVN_ALIROOT/trunk .
    else
      # We just have to update it
      Swallow -f "Updating AliRoot to latest trunk" svn up --non-interactive
    fi
  else
    # No trunk: just download, never update
    if [ ! -d "STEER" ]; then
      Swallow -f "Downloading AliRoot $ALICE_VER" \
        svn co $SVN_ALIROOT/tags/$ALICE_VER .
    fi
  fi

  Swallow -f "Moving into AliRoot build directory" cd "$ALICE_BUILD"

  if [ ! -e "Makefile" ]; then
    Swallow -f "Bootstrapping AliRoot build with cmake" cmake "$ALICE_ROOT"
  fi

  SwallowProgress -f "Building AliRoot" make -j$MJ

  Swallow -f "Symlinking AliRoot include directory" \
    ln -nfs "$ALICE_BUILD"/include "$ALICE_ROOT"/include

  Swallow -f "Sourcing envvars" SourceEnvVars

  if [ "$DISPLAY" != "" ]; then
    # Non-fatal
    Swallow "Testing ROOT with AliRoot libraries" \
      root -l -q "$ALICE_ROOT"/macros/loadlibs.C
  fi

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
  SwallowEnd "$OP" $RET $TSSTART $TSEND "$@"

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
  Swallow -f "Sourcing envvars" SourceEnvVars
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
  Swallow -f "Sourcing envvars" SourceEnvVars

  mkdir -p "$ALICE_PREFIX" 2> /dev/null

  if [ "$USER" == "root" ]; then
    Swallow -f "Creating ALICE software directory" [ -d "$ALICE_PREFIX" ]
    Swallow -f "Opening permissions of ALICE directory" \
      chmod 0777 "$ALICE_PREFIX"
  else
    TF="$ALICE_PREFIX/dummy_$RANDOM"
    touch "$TF" 2> /dev/null
    if [ $? != 0 ]; then
      Fatal "Not enough permissions: please run \"sudo $0 --prepare\""
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

# Prints out a nice help
function Help() {
  echo ""
  echo "$(basename $0) -- by Dario Berzano <dario.berzano@cern.ch>"
  echo ""
  echo "Tries to performs automatic installation of the ALICE framework."
  echo "The installation procedure follows exactly the steps described on:"
  echo ""
  echo "  http://newton.ph.unito.it/~berzano/w/doku.php?id=alice:compile"
  echo ""
  echo "Usage:"
  echo ""

  echo "  To create dirs (do it only the first time, as root if needed):"
  echo "    [sudo|su -c] $0 --prepare"
  echo ""

  echo "  To build/install/update something (multiple choices allowed): "
  echo "    $0 [--alien] [--root] [--geant3] [--aliroot] [--ncores <n>]"
  echo ""
  echo "  Note that build/install/update as root user is disallowed."
  echo "  With optional --ncores <n> you specify the number of parallel builds."
  echo "  If nothing is specified, the default value (#cores + 1) is used."
  echo ""

  echo "  To build/install/update everything (do --prepare first): "
  echo "    $0 --all"
  echo ""

  SourceEnvVars > /dev/null 2> /dev/null
  if [ "$?" != 0 ]; then
    echo "Please put alice-install.sh and alice-env.sh in the same directory!"
    echo "Environment script is expected in:"
    echo ""
    echo "  $ENVSCRIPT"
  else
    echo "ALICE environment is read from:"
    echo ""
    echo "  $ENVSCRIPT"
    echo ""
    echo "Software will be installed in (make with --prepare at first place):"
    echo ""
    echo "  $ALICE_PREFIX"
    echo ""
    echo "Versions of software that will be installed:"
    echo ""
    echo "  AliEn:   always the latest version"
    echo "  ROOT:    $ROOT_VER"
    echo "  Geant3:  $G3_VER"
    echo "  AliRoot: $ALICE_VER"
    echo ""
    echo "Choose them in alice-env.sh script with TRIADS and N_TRIAD vars."
  fi
  echo ""

  # Error message, if any
  if [ "$1" != "" ]; then
    echo -e '>> \033[1;31m'$1'\033[m'
    echo ""
  fi

}

# Main function
function Main() {

  local DO_PREP=0
  local DO_ALIEN=0
  local DO_ROOT=0
  local DO_G3=0
  local DO_ALICE=0

  local N_INST=0
  local PARAM

  # Environment script
  ENVSCRIPT=`dirname "$0"`
  ENVSCRIPT=`cd "$ENVSCRIPT" ; pwd`
  ENVSCRIPT="$ENVSCRIPT"/alice-env.sh

  if [ ! -r "$ENVSCRIPT" ]; then
    Help
    exit 1
  fi

  # Parse parameters
  while [ $# -gt 0 ]; do
    if [ "${1:0:2}" == "--" ]; then
      PARAM="${1:2}"
      case "$PARAM" in

        prepare)
          DO_PREP=1
        ;;

        alien)
          DO_ALIEN=1
        ;;

        root)
          DO_ROOT=1
        ;;

        geant3)
          DO_G3=1
        ;;

        aliroot)
          DO_ALICE=1
        ;;

        all)
          DO_ALIEN=1
          DO_ROOT=1
          DO_G3=1
          DO_ALICE=1
        ;;

        ncores)
          NCORES="$2"
          expr "$NCORES" + 0 > /dev/null 2> /dev/null
          if [ $? != 0 ]; then
            Help "--ncores must be followed by a number greater than zero"
            exit 1
          fi
          shift
        ;;

        *)
          Help "Unrecognized parameter: $1"
          exit 1
        ;;

      esac
    else
      Help "Unrecognized parameter: $1"
      exit 1
    fi
    shift
  done

  # How many build actions?
  let N_INST=DO_ALIEN+DO_ROOT+DO_G3+DO_ALICE

  if [ $DO_PREP == 0 ] && [ $N_INST == 0 ]; then
    Help "Nothing to do"
    exit 1
  elif [ $DO_PREP == 1 ] && [ $N_INST -gt 0 ]; then
    Help "Can't prepare and update/build/install something at the same time"
    exit 1
  elif [ "$USER" == "root" ] && [ $N_INST -gt 0 ]; then
    Help "I'm refusing to continue the installation as root user"
    exit 1
  fi

  # Remove spurious log files left
  RemoveLogs

  # Where are the logfiles?
  echo ""
  echo "Installation log files can be consulted on:"
  echo ""
  echo "  stderr: $ERR"
  echo "  stdout: $OUT"
  echo ""

  # Perform required actions
  if [ $DO_PREP == 1 ]; then
    ModulePrepare
  else
    SourceEnvVars > /dev/null 2>&1

    if [ $MJ == 1 ]; then
      echo "Building on single core (no parallel build)"
    else
      echo "Building using $MJ cores"
    fi

    [ $DO_ALIEN == 1 ] && ModuleAliEn
    [ $DO_ROOT  == 1 ] && ModuleRoot
    [ $DO_G3    == 1 ] && ModuleGeant3
    [ $DO_ALICE == 1 ] && ModuleAliRoot
  fi

  # Remove logs: if we are here, everything went right, so no need to see the
  # logs
  RemoveLogs

  echo ""
}

Main "$@"
