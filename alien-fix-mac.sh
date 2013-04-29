#!/bin/bash

#
# Global variables
#

export LOG="$HOME/alien-relocation.log"
export COUNT_ERR=0
export COUNT_TOT=0

#
# Functions
#

# Log facility
function Log() {
  let COUNT_TOT++
  if [ $2 == 0 ]; then
    STAT=" OK "
  else
    STAT="FAIL"
    let COUNT_ERR++
  fi
  echo "[$STAT] $1"
  echo "[$STAT] $1" >> $LOG
}

# Symlink to .so and relocation
function ProcessLib() {

  local LIBNAME LIBDIR LIBID POSTFIX OWD S
  LIBNAME="$1"

  LIBDIR=`dirname $LIBNAME`
  LIBNAME=`basename $LIBNAME`

  OWD=`pwd`
  cd "$LIBDIR"

  # Symbolic links
  ln -nfs "$LIBNAME."dylib "$LIBNAME."so
  Log "Symlink of $LIBDIR/$LIBNAME.dylib to $LIBNAME.so" $?

  # Perms
  chmod 0644 "$LIBDIR/$LIBNAME."dylib

  # If the library is a symlink, skip it
  #if [ -L "$LIBDIR/$LIBNAME."dylib ]; then
  #  return
  #fi

  # Change library id (first output of otool -L, or otool -D)
  LIBID=`otool -D "$LIBNAME."dylib | grep -v ':$'`
  if [[ "$LIBID" =~ ^/opt/alien/(.*) ]]; then
    POSTFIX="${BASH_REMATCH[1]}"
    install_name_tool -id "$ALIEN_DIR/$POSTFIX" "$LIBNAME."dylib 2> /dev/null
    Log "Change library ID of $LIBDIR/$LIBNAME.dylib from $LIBID to $ALIEN_DIR/$POSTFIX" $?
  fi

  # Change hardcoded library paths (from otool -L)
  otool -L "$LIBNAME."dylib | grep -v ':$' | cut -f2 | cut -f1 -d' ' |
  while read S
  do
    if [ ! -e "$S" ]; then
      if [[ "$S" =~ ^/opt/alien/(.*) ]]; then
        POSTFIX="${BASH_REMATCH[1]}"
        install_name_tool -change "$S" "$ALIEN_DIR/$POSTFIX" "$LIBNAME."dylib 2> /dev/null
        Log "Change library dependency of $LIBDIR/$LIBNAME.dylib from $S to $ALIEN_DIR/$POSTFIX" $?
      fi
    fi
  done

  cd "$OWD"
}

# Main function
function Main() {

  local R S LIBNAME LIBDIR OWD

  if [ "$ALIEN_DIR" == "" ]; then
    echo "\$ALIEN_DIR envvar not set"
    exit 1
  fi

  ALIEN_TEMP=`mktemp /tmp/alien_dylib_temp_XXXXXX`
  OWD=`pwd`
  cd "$ALIEN_DIR"
  find . -name '*.dylib' > $ALIEN_TEMP
  cd "$OWD"
  while read R
  do

    R=$ALIEN_DIR/${R:2}

    if [[ "$R" =~ ^(.*).dylib$ ]]; then
      LIBNAME=${BASH_REMATCH[1]}
      ProcessLib "$LIBNAME"
    fi

  done < $ALIEN_TEMP
  rm $ALIEN_TEMP

  echo ""
  echo "Actions done: $COUNT_TOT"
  echo "Errors: $COUNT_ERR"
  echo ""
  echo "Output saved on $LOG"

}

#
# Entry point
#

Main "$@"
