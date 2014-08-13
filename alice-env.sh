#
# alice-env.sh -- by Dario Berzano <dario.berzano@cern.ch>
#
# Prepares the environment for running the ALICE Framework, in particular:
#
#   AliEn
#   ROOT
#   Geant 3
#   AliRoot
#
# It optionally supports:
#
#   FastJet
#   FastJet Contrib
#
# This script is tested to work under Ubuntu and OS X. For more information on
# compatibility and build instructions, please consult:
#
#   https://dberzano.github.io/alice/install-aliroot/
#

################################################################################
#                                                                              #
#                      * * * DON'T TOUCH THIS FILE! * * *                      #
#                                                                              #
# Configuration variables are found in a separate file, in the same directory  #
# of this script:                                                              #
#                                                                              #
#   alice-env.conf                                                             #
#                                                                              #
# Or if you prefer, you can create a hidden file in your home:                 #
#                                                                              #
#   ~/.alice-env.conf                                                          #
#                                                                              #
# If none of the configuration files is found, a default alice-env.conf is     #
# created in the same directory of this script.                                #
#                                                                              #
# This script gets updated automatically, so any change you make will be lost. #
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

  M="Please select an AliRoot triad in the form \033[35mROOT / Geant3 /"
  M="$M AliRoot [/ FastJet]\033[m.\n"
  M="${M}You can also source with \033[33m-n\033[m"
  M="$M to skip this menu, or with \033[33m-c\033[m to clean the environment):"

  echo -e "\n$M\n"
  for ((C=1; $C<=${#TRIAD[@]}; C++)); do
    echo -e "  \033[36m($C)\033[m "$(NiceTriad ${TRIAD[$C]})
  done
  echo "";
  echo -e "  \033[36m(0)\033[m \033[33mClear environment\033[m"
  while [ 1 ]; do
    echo ""
    echo -n "Your choice: "
    read -n1 N_TRIAD
    echo ""
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
  AliRemovePaths PATH alien_cp aliroot root fastjet-config
  AliRemovePaths LD_LIBRARY_PATH libCint.so libSTEER.so libXrdSec.so \
    libgeant321.so libgapiUI.so libfastjet.so libfastjet.dylib
  AliRemovePaths DYLD_LIBRARY_PATH libCint.so libSTEER.so libXrdSec.so \
    libgeant321.so libgapiUI.so libfastjet.so libfastjet.dylib
  AliRemovePaths PYTHONPATH ROOT.py 

  # Restore prompt
  [ "$ALIPS1" == '' ] || export PS1="$ALIPS1"
  unset ALIPS1

  # Unset other environment variables and aliases
  unset MJ ALIEN_DIR GSHELL_ROOT ROOTSYS ALICE ALICE_ROOT ALICE_BUILD \
    ALICE_TARGET GEANT3DIR X509_CERT_DIR ALICE FASTJET \
    ALI_EnvScript ALI_Conf ALICE_ENV_UPDATE_URL ALICE_ENV_DONT_UPDATE
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
  export X509_CERT_DIR="$ALIEN_DIR/globus/share/certificates"

  # AliEn source installation uses a different destination directory
  [ -d "$X509_CERT_DIR" ] || X509_CERT_DIR="$ALIEN_DIR/api/share/certificates"

  export GSHELL_ROOT="$ALIEN_DIR/api"
  export PATH="$PATH:$GSHELL_ROOT/bin"
  export LD_LIBRARY_PATH="$LD_LIBRARY_PATH:$GSHELL_ROOT/lib"
  export DYLD_LIBRARY_PATH="$DYLD_LIBRARY_PATH:$GSHELL_ROOT/lib"

  #
  # ROOT
  #

  export ROOTSYS="$ALICE_PREFIX/root/$ROOT_SUBDIR"
  export PATH="$ROOTSYS/bin:$PATH"
  export LD_LIBRARY_PATH="$LD_LIBRARY_PATH:$ROOTSYS/lib"
  export ROOT_VER
  if [ -e "$ROOTSYS/lib/ROOT.py" ]; then
    # PyROOT support
    export PYTHONPATH="$ROOTSYS/lib:$PYTHONPATH"
  fi

  #
  # AliRoot
  #

  export ALICE="$ALICE_PREFIX"
  export ALICE_VER

  # Let's detect AliRoot CMake builds
  if [ ! -e "$ALICE_PREFIX/aliroot/$ALICE_SUBDIR/Makefile" ]; then
    export ALICE_ROOT="$ALICE_PREFIX/aliroot/$ALICE_SUBDIR/src"
    export ALICE_BUILD="$ALICE_PREFIX/aliroot/$ALICE_SUBDIR/build"
  else
    export ALICE_ROOT="$ALICE_PREFIX/aliroot/$ALICE_SUBDIR"
    export ALICE_BUILD="$ALICE_ROOT"
  fi

  export ALICE_TARGET=`root-config --arch 2> /dev/null`
  export PATH="$PATH:${ALICE_BUILD}/bin/tgt_${ALICE_TARGET}"
  export LD_LIBRARY_PATH="$LD_LIBRARY_PATH:${ALICE_BUILD}/lib/tgt_${ALICE_TARGET}"
  export DYLD_LIBRARY_PATH="$DYLD_LIBRARY_PATH:${ALICE_BUILD}/lib/tgt_${ALICE_TARGET}"

  #
  # Geant 3
  #

  export GEANT3DIR="$ALICE_PREFIX/geant3/$G3_SUBDIR"
  export LD_LIBRARY_PATH="$LD_LIBRARY_PATH:$GEANT3DIR/lib/tgt_${ALICE_TARGET}"
  export G3_VER

  #
  # FastJet
  #

  if [ "$FASTJET_VER" != '' ] ; then

    # Export FastJet variables only if we mean to have FastJet

    # Do we have contrib?
    FJCONTRIB_VER=${FASTJET_VER##*_}
    if [ "$FJCONTRIB_VER" != "$FASTJET_VER" ] && [ "$FJCONTRIB_VER" != '' ] ; then
      export FJCONTRIB_VER
      export FASTJET_VER="${FASTJET_VER%_*}"
    fi

    export FASTJET="$ALICE_PREFIX/fastjet/$FASTJET_SUBDIR"
    export FASTJET_VER
    if [ -d "$FASTJET/bin" ] && [ -d "$FASTJET/lib" ] ; then
      export PATH="$PATH:$FASTJET/bin"
      export LD_LIBRARY_PATH="$LD_LIBRARY_PATH:$FASTJET/lib"
    fi
  else
    unset FASTJET_VER FASTJET_SUBDIR
  fi

  #
  # Git prompt
  #

  export ALIPS1="$PS1"
  export PS1='`AliPrompt`'"$PS1"

}

# Prompt with current Git revision
function AliPrompt() {
  local REF=`git rev-parse --abbrev-ref HEAD 2> /dev/null`
  local COL_GIT="\033[35mgit:\033[m"
  if [ "$REF" == 'HEAD' ] ; then
    echo -e "\n$COL_GIT \033[33myou are not currently on any branch\033[m"
  elif [ "$REF" != '' ] ; then
    echo -e "\n$COL_GIT \033[33myou are currently on branch \033[36m$REF\033[m"
  fi
  echo '[AliEnv] '
}

# Prints out the ALICE paths. In AliRoot, the SVN revision number is also echoed
function AliPrintVars() {

  local WHERE_IS_G3 WHERE_IS_ALIROOT WHERE_IS_ROOT WHERE_IS_ALIEN \
    WHERE_IS_ALISRC WHERE_IS_ALIINST WHERE_IS_FASTJET ALIREV MSG LEN I
  local NOTFOUND='\033[31m<not found>\033[m'

  # Check if Globus certificate is expiring soon
  local CERT="$HOME/.globus/usercert.pem"
  which openssl > /dev/null 2>&1
  if [ $? == 0 ]; then
    if [ -r "$CERT" ]; then
      openssl x509 -in "$CERT" -noout -checkend 0 > /dev/null 2>&1
      if [ $? == 1 ]; then
        MSG="Your certificate has expired"
      else
        openssl x509 -in "$CERT" -noout -checkend 604800 > /dev/null 2>&1
        if [ $? == 1 ]; then
          MSG="Your certificate is going to expire in less than one week"
        fi
      fi
    else
      MSG="Can't find certificate $CERT"
    fi
  fi

  # Print a message if an error checking the certificate has occured
  if [ "$MSG" != "" ]; then
    echo -e "\n\033[41m\033[37m!!! ${MSG} !!!\033[m"
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
  if [ -r "$ALICE_BUILD/bin/tgt_$ALICE_TARGET/aliroot" ]; then
    WHERE_IS_ALIINST="$ALICE_BUILD"
    # Try to fetch svn revision number
    ALIREV=$(cat "$ALICE_BUILD/include/ARVersion.h" 2>/dev/null |
      perl -ne 'if (/ALIROOT_SVN_REVISION\s+([0-9]+)/) { print "$1"; }')
    [ "$ALIREV" != "" ] && \
      WHERE_IS_ALIINST="$WHERE_IS_ALIINST \033[33m(rev. $ALIREV)\033[m"
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

  # Detect FastJet location
  if [ -e "$FASTJET/lib/libfastjet.so" ] || \
    [ -e "$FASTJET/lib/libfastjet.dylib" ]; then
    WHERE_IS_FASTJET="$FASTJET"
  else
    WHERE_IS_FASTJET="$NOTFOUND"
  fi

  echo ""
  echo -e "  \033[36mAliEn\033[m            $WHERE_IS_ALIEN"
  echo -e "  \033[36mROOT\033[m             $WHERE_IS_ROOT"
  echo -e "  \033[36mGeant3\033[m           $WHERE_IS_G3"
  if [ "$FASTJET" != '' ] ; then
    echo -e "  \033[36mFastJet\033[m          $WHERE_IS_FASTJET"
  fi
  echo -e "  \033[36mAliRoot source\033[m   $WHERE_IS_ALISRC"
  echo -e "  \033[36mAliRoot build\033[m    $WHERE_IS_ALIINST"
  echo ""

}

# Separates version from directory, if triad is expressed in the form
# directory(version). If no (version) is expressed, dir is set to version for
# backwards compatiblity
function ParseVerDir() {

  local VERDIR="$1"
  local DIR_VAR="$2"
  local VER_VAR="$3"

  # Perl script to separate dirname/version
  local PERL='/^([^()]+)\((.+)\)$/ and '
  PERL="$PERL"' print "'$DIR_VAR'=$1 ; '$VER_VAR'=$2" or '
  PERL="$PERL"' print "'$DIR_VAR'='$VERDIR' ; '$VER_VAR'='$VERDIR'"'

  # Perl
  eval "unset $DIR_VAR $VER_VAR"
  eval `echo "$VERDIR" | perl -ne "$PERL"`

}

# Echoes a triad in a proper way, supporting the format directory(version) and
# also the plain old format where dir==ver for backwards compatiblity
function NiceTriad() {
  export D V
  local C=0
  for T in $@ ; do
    ParseVerDir $T D V
    if [ "$D" != "$V" ]; then
      echo -n "\033[35m$D\033[m ($V)"
    else
      echo -n "\033[35m$D\033[m"
    fi
    let C++
    [ $C != $# ] && echo -n ' / '
  done
  unset D V
}

# Tries to source the first configuration file found. Returns nonzero on error
function AliConf() {

  local OPT_QUIET="$1"
  local ALI_ConfFound ALI_ConfFiles

  # Normalize path to this script
  ALI_EnvScript="${BASH_SOURCE}"
  if [ "${ALI_EnvScript:0:1}" != '/' ] ; then
    ALI_EnvScript="${PWD}/${BASH_SOURCE}"
  fi
  ALI_EnvScript=$( cd "${ALI_EnvScript%/*}" ; pwd )"/${ALI_EnvScript##*/}"

  # Configuration file path: the first file found is loaded
  ALI_ConfFiles=( "${ALI_EnvScript%.*}.conf" "$HOME/.alice-env.conf" )
  for ALI_Conf in "${ALI_ConfFiles[@]}" ; do
    if [ -r "$ALI_Conf" ] ; then
      source "$ALI_Conf" > /dev/null 2>&1
      ALI_ConfFound=1
      break
    fi
  done

  if [ "$ALI_ConfFound" != 1 ] ; then
    # No configuration file found: create a default one
    echo -e "\033[33mNo configuration file found.\033[m"
    echo

    ALI_Conf="${ALI_ConfFiles[0]}"
    cat > "$ALI_Conf" <<_EoF_
#!/bin/bash

# Automatically created by alice-env.sh on $( LANG=C date )

#
# Triads: they start from 1 (not 0) and must be consecutive
#
# Format:
#   TRIAD[n]='ROOT Geant3 AliRoot [FastJet[_FJContrib]]'
#
# FastJet is optional. FJ Contrib is optional with FastJet 2 and mandatory with
# FastJet 3.
#

# No FastJet
TRIAD[1]='v5-34-18 v1-15a master'

# FastJet 2
#TRIAD[2]='v5-34-18 v1-15a master 2.4.5'

# FastJet 3
#TRIAD[3]='v5-34-18 v1-15a master 3.0.6_1.012'

# You can add more triads
#TRIAD[4]='...'

# Default triad for automatic installation 
export N_TRIAD=1
_EoF_

    if [ $? != 0 ] ; then
      echo -e "\033[31mUnable to create default configuration:\033[m"
      echo -e "  \033[36m${ALI_Conf}\033[m" ; echo
      echo -e "\033[31mCheck your permissions.\033[m"
      return 2
    else
      echo "A default one has been created. Find it at:"
      echo -e "  \033[36m${ALI_Conf}\033[m" ; echo
      echo "Edit it according to your needs, then source the environment again."
      return 1
    fi
  fi

  if [ ${#TRIAD[@]} == 0 ] ; then
    echo -e "\033[33mNo \"triads\" found in config file $ALI_Conf, aborting.\033[m"
    return 2
  fi

  # Auto-detect the ALICE_PREFIX
  export ALICE_PREFIX="${ALI_EnvScript%/*}"
  if [ "$OPT_QUIET" != 1 ] ; then
    echo -e "\nUsing config file \033[36m$ALI_Conf\033[m"
    echo -e "ALICE software directory is \033[36m${ALICE_PREFIX}\033[m"
  fi

  return 0
}

# Updates this very file, if necessary. Return codes:
#   0: nothing done
#   42: updated and changed, must re-source
#   1-9: no update, not an error
#   10-20: no update, an error occurred
# If you want to force-update:
#   AliUpdate 2
function AliUpdate() {

  local UpdUrl=${ALICE_ENV_UPDATE_URL:-https://raw.githubusercontent.com/dberzano/cern-alice-setup/master/alice-env.sh}
  local UpdStatus="${ALICE_PREFIX}/.alice-env.updated"
  local UpdTmp="${ALICE_PREFIX}/.alice-env.sh.new"
  local UpdBackup="${ALICE_PREFIX}/.alice-env.sh.old"
  local UpdLastUtc=$( cat "$UpdStatus" 2> /dev/null )
  UpdLastUtc=$( expr "$UpdLastUtc" + 0 2> /dev/null || echo 0 )
  local UpdNowUtc=$( date -u +%s )
  local UpdDelta=$(( UpdNowUtc - UpdLastUtc ))
  local UpdDeltaThreshold=43200  # update every 12 hours

  touch "$UpdTmp" 2> /dev/null || return 15  # cannot write

  if [ $UpdDelta -ge $UpdDeltaThreshold ] || [ "$1" == 2 ] ; then
    rm -f "$UpdTmp" || return 11
    curl -sL --max-time 5 "$UpdUrl" -o "$UpdTmp"
    if [ $? == 0 ] ; then
      echo $UpdNowUtc > "$UpdStatus"
      if ! cmp -s "$ALI_EnvScript" "$UpdTmp" ; then
        cp -f "$ALI_EnvScript" "$UpdBackup" || return 12
        mv "$UpdTmp" "$ALI_EnvScript" || return 13
        return 42  # updated ok, must resource
      else
        return 1  # no change
      fi
    else
      return 14  # dl failed
    fi
  fi

  return 0  # noop
}

# Main function: takes parameters from the command line
function AliMain() {

  local C T R
  local OPT_QUIET=0
  local OPT_NONINTERACTIVE=0
  local OPT_CLEANENV=0
  local OPT_DONTUPDATE=0
  local OPT_FORCEUPDATE=0
  local ARGS=("$@")

  # Parse command line options
  while [ $# -gt 0 ]; do
    case "$1" in
      "-q") OPT_QUIET=1 ;;
      "-v") OPT_QUIET=0 ;;
      "-n") OPT_NONINTERACTIVE=1 ;;
      "-i") OPT_NONINTERACTIVE=0 ;;
      "-c") OPT_CLEANENV=1; ;;
      "-k") OPT_DONTUPDATE=1 ;;
      "-u") OPT_FORCEUPDATE=1 ;;
    esac
    shift
  done

  # Always non-interactive+do not update when cleaning environment
  if [ "$OPT_CLEANENV" == 1 ]; then
    OPT_NONINTERACTIVE=1
    OPT_DONTUPDATE=1
    N_TRIAD=0
  fi

  # Try to load configuration
  AliConf "$OPT_QUIET"
  R=$?
  if [ $R != 0 ] ; then
    AliCleanEnv
    return $R
  fi

  # Update
  local DoUpdate
  if [ "$OPT_DONTUPDATE" == 1 ] ; then
    DoUpdate=0  # -k
  elif [ "$OPT_FORCEUPDATE" == 1 ] ; then
    DoUpdate=2  # -u
  elif [ "$ALICE_ENV_DONT_UPDATE" == 1 ] ; then
    DoUpdate=0
  else
    DoUpdate=1
  fi

  if [ $DoUpdate -gt 0 ]; then
    AliUpdate $DoUpdate
    ALI_rv=$?
    if [ $ALI_rv == 42 ] ; then
      # Script changed: re-source
      echo ; echo -e "\033[32mEnvironment script automatically updated to the latest version: reloading\033[m"
      source "$ALI_EnvScript" "${ARGS[@]}" -k
      return $?
    elif [ $ALI_rv -ge 10 ] ; then
      echo -e "Warning: automatic updater returned $ALI_rv"
    fi
  fi

  # Print menu if non-interactive
  [ "$OPT_NONINTERACTIVE" != 1 ] && AliMenu

  unset ROOT_VER G3_VER ALICE_VER FASTJET_VER FJCONTRIB_VER
  if [ $N_TRIAD -gt 0 ]; then
    C=0
    for T in ${TRIAD[$N_TRIAD]}
    do
      case $C in
        0) ROOT_VER=$T ;;
        1) G3_VER=$T ;;
        2) ALICE_VER=$T ;;
        3) FASTJET_VER=$T ;;
      esac
      let C++
    done

    # Separates directory name from version (backwards compatible)

    ParseVerDir "$ROOT_VER"    'ROOT_SUBDIR'    'ROOT_VER'
    ParseVerDir "$G3_VER"      'G3_SUBDIR'      'G3_VER'
    ParseVerDir "$ALICE_VER"   'ALICE_SUBDIR'   'ALICE_VER'
    ParseVerDir "$FASTJET_VER" 'FASTJET_SUBDIR' 'FASTJET_VER'

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
    # Those variables are not cleaned by AliCleanEnv
    unset ALICE_PREFIX \
      ROOT_VER ROOT_SUBDIR \
      G3_VER G3_SUBDIR \
      ALICE_VER ALICE_SUBDIR \
      FASTJET_VER FASTJET_SUBDIR FJCONTRIB_VER \
      alien_API_USER AliPrompt
    if [ "$OPT_QUIET" != 1 ]; then
      echo -e "\033[33mALICE environment variables cleared\033[m"
    fi
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
ALI_rv=$?
unset N_TRIAD TRIAD
unset ALICE_ENV_LASTCHECK ALICE_ENV_REV ALICE_ENV_URL
unset AliCleanEnv AliCleanPathList AliExportVars AliMain AliMenu AliPrintVars \
  AliRemovePaths AliSetParallelMake AliConf
return $ALI_rv
