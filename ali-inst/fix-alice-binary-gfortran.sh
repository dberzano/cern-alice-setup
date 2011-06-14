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

# "Wrong" gfortran path (from Fink) hardcoded into binaries
export GFORTRAN_WRONG="/sw/lib/gcc4.5/lib/libgfortran.3.dylib"

# "Right" gfortran path to replace the wrong one
export GFORTRAN_RIGHT="/usr/local/gfortran/lib/libgfortran.3.dylib"

#
# Functions
#

# The fix function
function FixPaths() {

  local PREFIX="$1"
  local D F FN

  # We look inside bin and lib directories
  find "$PREFIX" -type d -and \( -name lib -or -name bin \) | \
  while read D
  do

    # We look for so/dylib files or files without extension (not symlinks)
    find "$D" -type f -and \
      \( -name '*.so' -or -name '*.dylib' -or -not -name '*.*' \) | \
    while read F
    do

      otool -L "$F" | grep "$GFORTRAN_WRONG" > /dev/null 2>&1
      if [ $? == 0 ]; then

        # Wrong gfortran found
        FN=$(basename "$F")
        echo -n "[....] $FN"
        chmod +w "$F" > /dev/null 2>&1 && \
          install_name_tool -change \
            "$GFORTRAN_WRONG" "$GFORTRAN_RIGHT" "$F" > /dev/null 2>&1

        if [ $? == 0 ]; then
          echo -e "\r[ \033[32mOK\033[m ] $FN"
        else
          echo -e "\r[\033[31mFAIL\033[m] $FN"
        fi

      fi
    done
  done
}

# The main function
function Main() {

  if [ "`uname`" != "Darwin" ]; then
    echo ""
    echo "This script is meant to be run only on Macs"
    echo ""
  elif [ -f env_aliroot.sh ] && [ -f env_root.sh ]; then
    FixPaths "$PWD"
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

exit 0

find $PREFIX -type d -and \( -name lib -or -name bin \) | \
while read D
do
  #echo "=== $D ==="
  find $D -type f -and \( -name '*.so' -or -name '*.dylib' -or -not -name '*.*' \) | \
  while read F
  do
    otool -L $F | grep "$GFORTRAN_WRONG" > /dev/null 2>&1
    if [ $? == 0 ]; then
      echo "Match: $F"
      install_name_tool -change "$GFORTRAN_WRONG" "$GFORTRAN_RIGHT" "$F"
    fi
  done
done
