#
# alice-alienx-env.sh - by Dario Berzano <dario.berzano@to.infn.it>
#
# This script is meant to be sourced in order to prepare the environment to run
# ALICE Offline Framework applications (AliEn, ROOT, Geant 3 and AliRoot).
#
# On a typical setup, only the first lines of this script ought to be changed.
#
# This script was tested under Ubuntu and Mac OS X.
#
# For updates: http://newton.ph.unito.it/~berzano/w/doku.php?id=alice:compile
#

#
# Customizable variables
#

# If the specified file exists, settings are read from there; elsewhere they
# are read directly from this file
if [ -r "$HOME/.alice-env.conf" ]; then
  source "$HOME/.alice-env.conf"
else

  # Installation prefix of everything
  export ALICE_PREFIX="/opt/alice"

  # By uncommenting this line, alien-token-init will automatically use the
  # variable as your default AliEn user without explicitly specifying it after
  # the command
  #export alien_API_USER="myalienusername"

  # Triads in the form "root geant3 aliroot". Index starts from 1, not 0.
  # More information: http://aliceinfo.cern.ch/Offline/AliRoot/Releases.html
  TRIAD[1]="v5-27-06b v1-11 trunk"
  TRIAD[2]="trunk v1-11 trunk"
  # ...add more "triads" here without skipping array indices...

  # This is the "triad" that will be selected in non-interactive mode.
  # Set it to the number of the array index of the desired "triad"
  export N_TRIAD=1

fi

################################################################################
#                                                                              #
#   * * * BEYOND THIS POINT THERE IS LIKELY NOTHING YOU NEED TO MODIFY * * *   #
#                                                                              #
################################################################################

#
# Functions
#

# Shows the user a list of configured AliRoot triads. The chosen triad number is
# saved in the external variable N_TRIAD. A N_TRIAD of 0 means to clean up the
# environment
function AliMenu() {

  local C R M

  M="Please select an AliRoot triad in the form \033[1;35mROOT Geant3"
  M="$M AliRoot\033[m (you can also\nsource with \033[1;33m-n\033[m to skip"
  M="$M this menu, or with \033[1;33m-c\033[m to clean the environment):"

  echo -e "\n$M\n"
  for ((C=1; $C<=${#TRIAD[@]}; C++)); do
    echo -e "  \033[1;36m($C)\033[m \033[1;35m${TRIAD[$C]}\033[m"
  done
  echo "";
  echo -e "  \033[1;36m(0)\033[m \033[1;33mClean environment\033[m"
  while [ 1 ]; do
    echo ""
    echo -n "Your choice: "
    read N_TRIAD
    expr "$N_TRIAD" + 0 > /dev/null 2>&1
    R=$?
    if [ "$N_TRIAD" != "" ]; then
      if [ $R -eq 0 ] || [ $R -eq 1 ]; then
        if [ "$N_TRIAD" -ge 0 ] && [ "$N_TRIAD" -lt $C ]; then
          break
        fi
      fi
    fi
    echo "Invalid choice."
  done

}

# Removes directories from the specified PATH-like variable that contain the
# given files. Variable is the first argument and it is passed by name, without
# the dollar sign; subsequent arguments are the files to search for
function AliRemovePaths() {

  local VARNAME=$1
  shift
  local DIRS=`eval echo \\$$VARNAME`
  local NEWDIRS=""
  local OIFS="$IFS"
  local D F KEEPDIR
  IFS=:

  for D in $DIRS
  do
    KEEPDIR=1
    if [ -d "$D" ]; then
      for F in $@
      do
        if [ -e "$D/$F" ]; then
          KEEPDIR=0
          break
        fi
      done
    else
      KEEPDIR=0
    fi
    if [ $KEEPDIR == 1 ]; then
      [ "$NEWDIRS" == "" ] && NEWDIRS="$D" || NEWDIRS="$NEWDIRS:$D"
    fi
  done

  IFS="$OIFS"

  eval export $VARNAME="$NEWDIRS"

}

# Cleans leading, trailing and double colons from the variable whose name is
# passed as the only argument of the string
function AliCleanPathList() {
  local VARNAME="$1"
  local STR=`eval echo \\$$VARNAME`
  local PREV_STR
  while [ "$PREV_STR" != "$STR" ]; do
    PREV_STR="$STR"
    STR=`echo "$STR" | sed s/::/:/g`
  done
  STR=${STR#:}
  STR=${STR%:}
  eval export $VARNAME=\"$STR\"
}

# Cleans up the environment from previously set (DY)LD_LIBRARY_PATH and PATH
# variables
function AliCleanEnv() {
  AliRemovePaths PATH xrdgsiproxy aliroot root
  AliRemovePaths LD_LIBRARY_PATH libCint.so libSTEER.so libXrdSec.so \
    libgeant321.so
  AliRemovePaths DYLD_LIBRARY_PATH libCint.so libSTEER.so libXrdSec.so \
    libgeant321.so

  # Unset other environment variables and aliases
  unset MJ ALIEN_DIR GSHELL_ROOT ROOTSYS ALICE ALICE_ROOT ALICE_INSTALL \
    ALICE_TARGET GEANT3DIR X509_CERT_DIR GSHELL_NO_GCC ALICE
}

# Sets the number of parallel workers for make to the number of cores plus one
# in external variable MJ
function AliSetParallelMake() {
  MJ=`grep -c bogomips /proc/cpuinfo 2> /dev/null`
  [ "$?" != 0 ] && MJ=`sysctl hw.ncpu | cut -b10 2> /dev/null`
  # If MJ is NaN, "let" treats it as "0": always fallback to 1 core
  let MJ++
  export MJ
}

# Exports variables needed to run AliRoot, based on the selected triad
function AliExportVars() {

  #
  # AliEn
  #

  export ALIEN_DIR="$ALICE_PREFIX/alien"

  if [ -e "$ALIEN_DIR/api/bin/aliensh" ]; then
    # Binary distribution installed with alien-installer
    export X509_CERT_DIR="$ALIEN_DIR/globus/share/certificates"
    export GSHELL_NO_GCC=1
    export GSHELL_ROOT="$ALIEN_DIR/api"
  else
    # Defaults to source distribution installed via xgapi
    export X509_CERT_DIR="$ALIEN_DIR/share/certificates"
    export GSHELL_ROOT="$ALIEN_DIR"
  fi

  export PATH="$PATH:$GSHELL_ROOT/bin"
  export LD_LIBRARY_PATH="$LD_LIBRARY_PATH:$GSHELL_ROOT/lib"
  export DYLD_LIBRARY_PATH="$DYLD_LIBRARY_PATH:$GSHELL_ROOT/lib"

  #
  # ROOT
  #

  export ROOTSYS="$ALICE_PREFIX/root/$ROOT_VER"
  export PATH="$ROOTSYS/bin:$PATH"
  export LD_LIBRARY_PATH="$LD_LIBRARY_PATH:$ROOTSYS/lib"

  #
  # AliRoot
  #

  export ALICE="$ALICE_PREFIX"

  # Let's detect AliRoot CMake builds
  if [ ! -e "$ALICE_PREFIX/aliroot/$ALICE_VER/Makefile" ]; then
    export ALICE_ROOT="$ALICE_PREFIX/aliroot/$ALICE_VER/src"
    export ALICE_INSTALL="$ALICE_PREFIX/aliroot/$ALICE_VER/build"
  else
    export ALICE_ROOT="$ALICE_PREFIX/aliroot/$ALICE_VER"
    export ALICE_INSTALL="$ALICE_ROOT"
  fi

  export ALICE_TARGET=`root-config --arch 2> /dev/null`
  export PATH="$PATH:${ALICE_INSTALL}/bin/tgt_${ALICE_TARGET}"
  export LD_LIBRARY_PATH="$LD_LIBRARY_PATH:${ALICE_INSTALL}/lib/tgt_${ALICE_TARGET}"
  export DYLD_LIBRARY_PATH="$DYLD_LIBRARY_PATH:${ALICE_INSTALL}/lib/tgt_${ALICE_TARGET}"

  #
  # Geant 3
  #

  export GEANT3DIR="$ALICE_PREFIX/geant3/$G3_VER"
  export LD_LIBRARY_PATH="$LD_LIBRARY_PATH:$GEANT3DIR/lib/tgt_${ALICE_TARGET}"
 
}

# Prints out the ALICE paths. In AliRoot, the SVN revision number is also echoed
function AliPrintVars() {

  local WHERE_IS_G3 WHERE_IS_ALIROOT WHERE_IS_ROOT WHERE_IS_ALIEN \
    WHERE_IS_ALISRC WHERE_IS_ALIINST ALIREV MSG LEN I
  local NOTFOUND='\033[1;31m<not found>\033[m'

  # Check if Globus certificate is expiring soon
  local CERT="$HOME/.globus/usercert.pem"
  which openssl > /dev/null 2>&1
  if [ $? == 0 ]; then
    if [ -r "$CERT" ]; then
      openssl x509 -in "$CERT" -noout -checkend 604800
      if [ $? == 1 ]; then
        MSG="Your certificate is going to expire before one week"
      else
        openssl x509 -in "$CERT" -noout -checkend 0
        if [ $? == 1 ]; then
          MSG="Your certificate is expired"
        fi
      fi
    else
      MSG="Can't find certificate $CERT"
    fi
  fi

  # Print a message if an error checking the certificate has occured
  if [ "$MSG" != "" ]; then
    echo -e "\n\033[41m\033[1;37m!!! ${MSG} !!!\033[m"
  fi

  # Detect Geant3 installation path
  if [ -x "$GEANT3DIR/lib/tgt_$ALICE_TARGET/libgeant321.so" ]; then
    WHERE_IS_G3="$GEANT3DIR"
  else
    WHERE_IS_G3="$NOTFOUND"
  fi

  # Detect AliRoot source location
  if [ -r "$ALICE_ROOT/CMakeLists.txt" ] || [ -r "$ALICE_ROOT/Makefile" ]; then
    WHERE_IS_ALISRC="$ALICE_ROOT"
  else
    WHERE_IS_ALISRC="$NOTFOUND"
  fi

  # Detect AliRoot build/install location
  if [ -r "$ALICE_INSTALL/bin/tgt_$ALICE_TARGET/aliroot" ]; then
    WHERE_IS_ALIINST="$ALICE_INSTALL"
    # Try to fetch svn revision number
    ALIREV=$(cat "$ALICE_INSTALL/include/ARVersion.h" 2>/dev/null |
      perl -ne 'if (/ALIROOT_SVN_REVISION\s+([0-9]+)/) { print "$1"; }')
    [ "$ALIREV" != "" ] && WHERE_IS_ALIINST="$WHERE_IS_ALIINST \033[1;33m(rev. $ALIREV)\033[m"
  else
    WHERE_IS_ALIINST="$NOTFOUND"
  fi

  # Detect ROOT location
  if [ -x "$ROOTSYS/bin/root.exe" ]; then
    WHERE_IS_ROOT="$ROOTSYS"
  else
    WHERE_IS_ROOT="$NOTFOUND"
  fi

  # Detect AliEn location
  if [ -x "$GSHELL_ROOT/bin/aliensh" ]; then
    WHERE_IS_ALIEN="$GSHELL_ROOT"
  else
    WHERE_IS_ALIEN="$NOTFOUND"
  fi

  echo ""
  echo -e "  \033[1;36mAliEn\033[m           $WHERE_IS_ALIEN"
  echo -e "  \033[1;36mROOT\033[m            $WHERE_IS_ROOT"
  echo -e "  \033[1;36mGeant3\033[m          $WHERE_IS_G3"
  echo -e "  \033[1;36mAliRoot source\033[m  $WHERE_IS_ALISRC"
  echo -e "  \033[1;36mAliRoot build\033[m   $WHERE_IS_ALIINST"
  echo ""

}

# Main function: takes parameters from the command line
function AliMain() {

  local C T
  local OPT_QUIET OPT_NONINTERACTIVE OPT_CLEANENV

  # Parse command line options
  while [ $# -gt 0 ]; do
    case "$1" in
      "-q") OPT_QUIET=1 ;;
      "-v") OPT_QUIET=0 ;;
      "-n") OPT_NONINTERACTIVE=1 ;;
      "-i") OPT_NONINTERACTIVE=0 ;;
      "-c") OPT_CLEANENV=1; ;;
    esac
    shift
  done

  # Always non-interactive when cleaning environment
  if [ "$OPT_CLEANENV" == 1 ]; then
    OPT_NONINTERACTIVE=1
    N_TRIAD=0
  fi

  [ "$OPT_NONINTERACTIVE" != 1 ] && AliMenu

  if [ $N_TRIAD -gt 0 ]; then
    C=0
    for T in ${TRIAD[$N_TRIAD]}
    do
      case $C in
        0) ROOT_VER=$T ;;
        1) G3_VER=$T ;;
        2) ALICE_VER=$T ;;
      esac
      let C++
    done
  else
    # N_TRIAD=0 means "clean environment"
    OPT_CLEANENV=1
  fi

  # Cleans up the environment from previous varaiables
  AliCleanEnv

  if [ "$OPT_CLEANENV" != 1 ]; then

    # Number of parallel workers (on variable MJ)
    AliSetParallelMake

    # Export all the needed variables
    AliExportVars

    # Prints out settings, if requested
    [ "$OPT_QUIET" != 1 ] && AliPrintVars

  else
    unset ALICE_PREFIX ROOT_VER G3_VER ALICE_VER
    [ "$OPT_QUIET" != 1 ] && echo -e "\033[1;33mALICE environment variables cleaned\033[m"
  fi

  # Cleans up artifacts in paths
  AliCleanPathList LD_LIBRARY_PATH
  AliCleanPathList DYLD_LIBRARY_PATH
  AliCleanPathList PATH

}

#
# Entry point
#

AliMain "$@"
unset N_TRIAD TRIAD
unset AliCleanEnv AliCleanPathList AliExportVars AliMain AliMenu AliPrintVars \
  AliRemovePaths AliSetParallelMake
