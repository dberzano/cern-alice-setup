#
# alice-alienx-env.sh - by Dario Berzano <dario.berzano@gmail.com>
#
# This script is meant to be sourced in order to prepare the environment to run
# ALICE Offline Framework applications (AliEn, ROOT, Geant 3 and Aliroot).
#
# On a typical setup, only the first lines of this script must be changed.
#
# This script was tested under Ubuntu and Mac OS X.
#
# For updates: http://newton.ph.unito.it/~berzano/w/doku.php?id=alice:compile
#

#
# Customizable variables
#

# Installation prefix of everything
export ALICE_PREFIX="/opt/alice"

# Your AliEn username
export alien_API_USER="myalienusername"

# Triads in the form "root geant3 aliroot". Index starts from 1, not 0.
# More information: http://aliceinfo.cern.ch/Offline/AliRoot/Releases.html
TRIAD[1]="v5-26-00b v1-11 trunk"
TRIAD[2]="trunk v1-11 trunk"
# ...add more "triads" here without skipping array indices...

# This is the "triad" that will be selected in non-interactive mode.
# Set it to the number of the array index of the desired "triad"
N_TRIAD=1

#
# Beyond this point there is likely nothing you need to modify
#

# Parse command line options
while [ $# -gt 0 ]; do
  case "$1" in
    "-q") OPT_QUIET=1 ;;
    "-v") OPT_QUIET=0 ;;
    "-n") OPT_NONINTERACTIVE=1 ;;
    "-i") OPT_NONINTERACTIVE=0 ;;
    "-c") OPT_CLEANENV=1; OPT_NONINTERACTIVE=1 ;;
  esac
  shift
done

#
# Interactive triad selection menu
#

if [ "$OPT_NONINTERACTIVE" != 1 ]; then
  echo ""
  echo " * Please select an Aliroot triad in the form \"ROOT Geant3 Aliroot\" (you can"
  echo "   source with \"-n\" to skip this menu, or with \"-c\" to clean the environment):"
  echo ""
  for ((C=1; $C<=${#TRIAD[@]}; C++)); do
    echo "     $C) ${TRIAD[$C]}"
  done
  echo "";
  echo "     0) Clean environment"
  while [ 1 ]; do
    echo ""
    echo -n " * Your choice: "
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
    echo " * Invalid choice."
  done
  unset R C T
fi

# 0 means "clean"
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
  OPT_CLEANENV=1
fi
unset C T N_TRIAD TRIAD

#
# Clean up environment from previously set LD_LIBRARY_PATH and PATH variables
#

OIFS="$IFS"
IFS=":"

# Examine path: search for xrdgsiproxy, root, aliroot executables
NEW_PATH=""
for P in $PATH
do
  if [ -d "$P" ] && \
     [ ! -x "$P/xrdgsiproxy" ] && \
     [ ! -x "$P/aliroot" ] && \
     [ ! -x "$P/root" ] && \
     [ "$P" != "" ]; then
    if [ "$NEW_PATH" == "" ]; then
      NEW_PATH="$P"
    else
      NEW_PATH="$NEW_PATH:$P"
    fi
  fi
done

# Examine libraries
NEW_LD_LIBRARY_PATH=""
for L in $LD_LIBRARY_PATH
do
  if [ -d "$L" ] && \
     [ ! -x "$L/libCint.so" ] && \
     [ ! -x "$L/libSTEER.so" ] && \
     [ ! -x "$L/libXrdSec.so" ] && \
     [ ! -x "$L/libgeant321.so" ] && \
     [ "$L" != "" ]; then
    if [ "$NEW_PATH" == "" ]; then
      NEW_LD_LIBRARY_PATH="$L"
    else
      NEW_LD_LIBRARY_PATH="$NEW_LD_LIBRARY_PATH:$L"
    fi
  fi
done

IFS="$OIFS"
unset OIFS L P

export PATH="$NEW_PATH"
export LD_LIBRARY_PATH="$NEW_LD_LIBRARY_PATH"

unset NEW_PATH NEW_LD_LIBRARY_PATH

# Unset other environment variables and aliases
unset MJ ALIEN_DIR GSHELL_ROOT ROOTSYS ALICE ALICE_ROOT ALICE_TARGET \
  G3SYS X509_CERT_DIR GSHELL_NO_GCC
unalias root aliroot > /dev/null 2>&1

# Quit if clean only
if [ "$OPT_CLEANENV" == 1 ]; then
  unset OPT_QUIET OPT_NONINTERACTIVE OPT_CLEANENV ALICE_PREFIX ALICE_VER \
    ROOT_VER G3_VER G3SYS
  echo ""
  echo " * Environment variables purged."
  echo ""
  return
fi

# Number of parallel make workers (num. of cores + 1)
MJ=`grep -c bogomips /proc/cpuinfo 2> /dev/null`
if [ "$?" != 0 ]; then
  MJ=`sysctl hw.ncpu | cut -b10 2> /dev/null`
fi
# If MJ is NaN, "let" treats it as "0": always fallback to 1 core
let MJ++
export MJ

################################################################################

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

#
# ROOT
#

export ROOTSYS="$ALICE_PREFIX/root/$ROOT_VER"
export PATH="$ROOTSYS/bin:$PATH"
export LD_LIBRARY_PATH="$LD_LIBRARY_PATH:$ROOTSYS/lib"

#
# GEANT 3
#

export G3SYS="$ALICE_PREFIX/geant3/$G3_VER"
export LD_LIBRARY_PATH="$LD_LIBRARY_PATH:$ALICE/geant3/lib/tgt_${ALICE_TARGET}"

#
# AliRoot
#

export ALICE_ROOT="$ALICE_PREFIX/aliroot/$ALICE_VER"
export ALICE_TARGET=`root-config --arch 2> /dev/null`
export PATH="$PATH:$ALICE_ROOT/bin/tgt_${ALICE_TARGET}"
export LD_LIBRARY_PATH="$LD_LIBRARY_PATH:$ALICE_ROOT/lib/tgt_${ALICE_TARGET}"

################################################################################

#
# AliEn environment variables and aliases
#

[ -e /tmp/gclient_env_$UID ] && source /tmp/gclient_env_$UID

alias alien-token-init='alien-token-destroy ; alien-token-init $alien_API_USER ; [ -e /tmp/gclient_env_$UID ] && source /tmp/gclient_env_$UID'
alias alien-token-destroy='alien-token-destroy ; xrdgsiproxy destroy'

#alias root='[ -e /tmp/gclient_env_$UID ] && [ "$GBBOX_ENVFILE" == "" ] && source /tmp/gclient_env_$UID ; root'
#alias aliroot='[ -e /tmp/gclient_env_$UID ] && [ "$GBBOX_ENVFILE" == "" ] && source /tmp/gclient_env_$UID ; aliroot'

#
# Remove initial colons from paths
#

export LD_LIBRARY_PATH=${LD_LIBRARY_PATH#:}
export PATH=${PATH#:}

#
# Echo variables
#

if [ "$OPT_QUIET" != 1 ]; then
  if [ -x "$G3SYS/lib/tgt_$ALICE_TARGET/libgeant321.so" ]; then
    WHERE_IS_G3="$G3SYS"
  else
    WHERE_IS_G3="<not found>"
  fi
  if [ -x "$ALICE_ROOT/bin/tgt_$ALICE_TARGET/aliroot" ]; then
    WHERE_IS_ALIROOT="$ALICE_ROOT"
    # Try to fetch svn revision number
    ALIREV=$(cat "$ALICE_ROOT/include/ARVersion.h" 2>/dev/null |
      perl -ne 'if (/ALIROOT_SVN_REVISION\s+([0-9]+)/) { print "$1"; }')
    WHERE_IS_ALIROOT="$WHERE_IS_ALIROOT (rev. $ALIREV)"
    unset ALIREV
  else
    WHERE_IS_ALIROOT="<not found>"
  fi
  if [ -x "$ROOTSYS/bin/root.exe" ]; then
    WHERE_IS_ROOT="$ROOTSYS"
  else
    WHERE_IS_ROOT="<not found>"
  fi
  if [ -x "$GSHELL_ROOT/bin/aliensh" ]; then
    WHERE_IS_ALIEN="$GSHELL_ROOT"
  else
    WHERE_IS_ALIEN="<not found>"
  fi
  echo ""
  echo " * AliEn:   $WHERE_IS_ALIEN"
  echo " * ROOT:    $WHERE_IS_ROOT"
  echo " * Geant3:  $WHERE_IS_G3"
  echo " * AliRoot: $WHERE_IS_ALIROOT"
  echo ""
  unset WHERE_IS_G3 WHERE_IS_ALIROOT WHERE_IS_ROOT WHERE_IS_ALIEN
fi

unset OPT_QUIET OPT_NONINTERACTIVE OPT_CLEANENV
