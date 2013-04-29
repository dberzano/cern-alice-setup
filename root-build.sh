#!/bin/bash

#
# A simple script to compile ROOT without tainting the environment
#

#
# Variables
#

export GSHELL_ROOT="/opt/alisw/alien/api"
export ROOTSYS
export CONFIGURE_LOG="log_configure"
export MAKE_LOG="log_make"
export TIME="/usr/bin/time"
export MAKE_WORKERS

# Compilers: GNU
export MY_CC=$(which gcc)
export MY_CXX=$(which g++)
export MY_LD=$(which g++)

# Compilers: clang
#export MY_CC="/opt/clang+llvm-v2.8/bin/clang"
#export MY_CXX="/opt/clang+llvm-v2.8/bin/clang++"
#export MY_LD="/opt/clang+llvm-v2.8/bin/clang++"

#
# Functions
#

# Init ROOT build
function Init() {
  cd $(dirname "$0")
  ROOTSYS=$(pwd)

  PATH=$ROOTSYS/bin:$PATH
  LD_LIBRARY_PATH=$ROOTSYS/lib:$LD_LIBRARY_PATH

  # Parallel build
  MAKE_WORKERS=`grep -c bogomips /proc/cpuinfo 2> /dev/null`
  [ "$?" != 0 ] && MAKE_WORKERS=`sysctl hw.ncpu | cut -b10 2> /dev/null`
  # If MAKE_WORKERS is NaN, "let" treats it as "0": always fallback to 1 core
  let MAKE_WORKERS++
}

# Configure ROOT
function Configure() {
  "$TIME" \
  ./configure \
      --with-cc="$MY_CC" \
      --with-cxx="$MY_CXX" \
      --with-ld="$MY_LD" \
      --with-f77=gfortran \
      --with-pythia6-uscore=SINGLE \
      --with-alien-incdir="$GSHELL_ROOT/include" \
      --with-alien-libdir="$GSHELL_ROOT/lib" \
      --with-xrootd="$GSHELL_ROOT" \
      --enable-minuit2 \
      --enable-roofit \
      --enable-soversion \
      --disable-bonjour \
  2>&1 | tee "$CONFIGURE_LOG"
}

# Make ROOT
function Make() {
  "$TIME" \
  make -j$MAKE_WORKERS \
  2>&1 | tee "$MAKE_LOG"
}

# Launch ROOT
function Launch() {
  root "$@"
  exit $?
}

# Help
function Help() {
  echo ""
  echo "Usage: $0 [--configure|--make]"
  echo ""
  echo "ROOT will be built with ROOTSYS=$ROOTSYS"
  echo "AliEn/xrootd will be taken from GSHELL_ROOT=$GSHELL_ROOT"
  echo ""
}

# Main function
function Main() {
  Init
  case "$1" in
    --config*) Configure ;;
    --make) Make ;;
    --launch) shift ; Launch "$@" ;;
    *) Help ;;
  esac
}

#
# Entry point
#

Main "$@"
