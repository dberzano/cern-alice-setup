#!/bin/bash

#
# fix-alice-binary-gfortran.sh -- by Dario Berzano <dario.berzano@cern.ch>
#
# Fixes the wrong path to libgfortran.3.dylib inside binaries and libraries from
# the precompiled version[1] of the ALICE framework for Mac OS X.
#
# [1] http://alimonitor.cern.ch/packages/
#
# The only requisite is to run this script from inside the directory containing
# the scripts used to set environment variables, i.e. env_aliroot.sh and
# env_root.sh
#

#
# Global variables
#

# "Wrong" library paths (from Fink) hardcoded into binaries
export WRONG=(
  "/sw/lib/gcc4.5/lib/libstdc++.6.dylib"
  "/sw/lib/gcc4.5/lib/libgfortran.3.dylib"
  "/sw/lib/gcc4.5/lib/libgcc_s.1.dylib"
  "/sw/lib/libcrypto.0.9.8.dylib"
  "/sw/lib/libjpeg.62.dylib"
  "/sw/lib/libssl.0.9.8.dylib"
  "/sw/lib/python2.6/config/libpython2.6.dylib"
)

# "Right" paths, to be searched automatically
export RIGHT=()

# Base search directories for the libraries, in order
export BASE=()

# Result of function LocateLib
export LOCATELIB_RES=""

#
# Functions
#

# The fix function
function FixPaths() {

  local PREFIX="$1"
  local DRY=0
  local D F FN T

  # Dry run?
  [ "$2" == "--dry" ] && DRY=1

  # Assemble command on a temporary file
  T=$(mktemp /tmp/chlib.XXXXX)
  echo -n "install_name_tool" > $T
  CNT=0
  for P in "${WRONG[@]}"; do
    echo -n " -change \"$P\" \"${RIGHT[$CNT]}\"" >> $T
    let CNT++
  done
  echo " \"\$1\"" >> $T

  # We look inside bin and lib directories
  find "$PREFIX" -type d -and \( -name lib -or -name bin \) | \
  while read D
  do

    # We look for so/dylib files or files without extension (not symlinks)
    find "$D" -type f -and \
      \( -name '*.so' -or -name '*.dylib' -or -not -name '*.*' \) | \
    while read F
    do

      # Limit search to all paths containing /sw (Fink)
      otool -L "$F" | grep "/sw" > /dev/null 2>&1
      if [ $? == 0 ]; then

        # Wrong full path of a library found
        FN=$(basename "$F")
        echo -n "[....] $FN"
        if [ "$DRY" == 0 ]; then

          chmod +w "$F" > /dev/null 2>&1 && \
            source $T "$F"

          if [ $? == 0 ]; then
            echo -e "\r[ \033[32mOK\033[m ] $FN"
          else
            echo -e "\r[\033[31mFAIL\033[m] $FN"
          fi

        else
          # Dry run
          echo -e "\r[\033[35mNOOP\033[m] $FN"
        fi

      fi
    done
  done

  rm -f $T
}

# Find right library named "$1" under "$2"
function LocateLib() {

  local NAME="$1"
  local BASE="$2"

  LOCATELIB_RES=""

  local T=$(mktemp /tmp/locate_gfortran.XXXXX)

  echo -en "\r[....] Searching for $NAME under $BASE"

  # Try with mdfind first
  mdfind -name "$NAME" -onlyin "$BASE" > "$T" 2> /dev/null

  if [ ! -s "$T" ]; then
    # Nothing was found with mdfind... try with find instead
    find "$BASE" -name "$NAME" > "$T" 2> /dev/null
  fi

  if [ ! -s "$T" ]; then
    # Nothing was found neither with mdfind, nor with find... failure
    echo -e "\r[\033[31mFAIL\033[m]"
    rm -f $T
    return 1
  else
    # Found: take the first result
    LOCATELIB_RES=$(head -n1 $T)
    echo -e "\r[\033[32m OK \033[m] $NAME has been found as $LOCATELIB_RES"
  fi

  rm -f $T

  return 0
}

# The main function
function Main() {

  local DRY P CNT THISNAME THISBASE
  local NERR=0

  # Parse parameters
  while [ $# -gt 0 ]; do
    case "$1" in

      --dry)
        DRY=1
      ;;

      --base-dir)
        THISNAME="$2"
        THISBASE="$3"
        CNT=0
        for P in "${WRONG[@]}"; do
          if [ "$(basename "$P")" == "$THISNAME" ]; then
            BASE[$CNT]="$THISBASE"
          fi
          let CNT++
        done
        shift 2
      ;;

      *)
        echo "Unrecognized switch: $1"
        let NERR++
      ;;

    esac
    shift
  done

  # Are there any errors?
  if [ $NERR -gt 0 ]; then
    echo "Aborting."
    exit 1
  fi

  if [ "`uname`" != "Darwin" ]; then
    echo ""
    echo "This script is meant to be run only on Macs"
    echo ""
  elif [ -f env_aliroot.sh ] && [ -f env_root.sh ]; then

    # Search for each library path in order, abort on error
    CNT=0
    for P in "${WRONG[@]}"; do
      THISBASE="${BASE[$CNT]}"
      if [ "$THISBASE" == "" ]; then
        LocateLib $(basename "$P") "/usr/lib" || \
          LocateLib $(basename "$P") "/" || return 1
      else
        LocateLib $(basename "$P") "$THISBASE" || return 1
      fi
      RIGHT[$CNT]="$LOCATELIB_RES"
      let CNT++
    done

    # Fix paths (if not dry run)
    [ "$DRY" == 1 ] && FixPaths "$PWD" --dry || FixPaths "$PWD"

  else
    echo ""
    echo "This script must be run from within the directory containing:"
    echo ""
    echo " * env_aliroot.sh"
    echo " * env_root.sh"
    echo ""
  fi

}

#
# Entry point
#

Main "$@"
