#!/bin/bash

# Fix function: takes root search directory as the only argument
function fixMakefile() {

  #local FIX_SU=`testFixSecondUnderscore`
  local FIX_SU=1
  local FIX_DYLIB=1

  find "$1" -name 'Makefile\.macosx*' -and -not -path '*\.svn*' |
  while read F
  do
    egrep "libgfortran.dylib|no-second-underscore" "$F" > /dev/null
    if [ $? == 0 ]; then
      echo -n "Fixing $F..."
      if [ $FIX_SU == 1 ]; then
        sed -i '' 's/-fno-second-underscore//' "$F"
      fi
      if [ $FIX_DYLIB == 1 ]; then
        sed -i '' 's/libgfortran\.dylib/libgfortran.a/' "$F"
      fi
      echo "done"
    fi
  done

  echo "*** Use \"svn revert\" to restore modified files ***"
}

# Tests if we need to fix the no-second-underscore issue
function testFixSecondUnderscore() {
  local T="/tmp/test-fix-su"

  cat > "$T.f" <<EOF
      program hello
         print *,"Hello World!"
      end program hello
EOF
  gfortran -fno-second-underscore "$T.f" -o "$T.out" #> /dev/null 2>&1
  local R=$?
  rm -f "$T.f" "$T.out"
  if [ $R == 1 ]; then
    echo 1
  else
    echo 0
  fi
}

# Fix ROOT
if [ "$1" == "--root" ]; then
  if [ -d "$ROOTSYS" ]; then
    fixMakefile "$ROOTSYS"
  else
    echo "Set \$ROOTSYS to fix ROOT installation." >&2
  fi
# Fix AliRoot
elif [ "$1" == "--aliroot" ]; then
  if [ -d "$ALICE_ROOT" ]; then
    fixMakefile "$ALICE_ROOT"
  else
    echo "Set \$ALICE_ROOT to fix AliRoot installation." >&2
  fi
else
  echo "Usage: $0 [--root|--aliroot]"
fi
