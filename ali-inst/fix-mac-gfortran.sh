#!/bin/bash

# Fix function: takes root search directory as the only argument
function FixCommon() {

  local F

  find "$1" -name 'Makefile\.macosx*' -and -not -path '*\.svn*' |
  while read F
  do
    egrep "libgfortran.dylib|no-second-underscore" "$F" > /dev/null
    if [ $? == 0 ]; then
      echo -n "Fixing $F..."
      sed -i '' 's/-fno-second-underscore//' "$F"
      sed -i '' 's/libgfortran\.dylib/libgfortran.a/' "$F"
      echo "done"
    fi
  done

}

# Specific AliRoot fixes
function FixAliRoot() {

  local F
  local DEST

  # -ffree-form introduced in LHAPDF since trunk around r42469
  find "$1/LHAPDF" \( -name '*Makefile*' -or -name '*.pkg' \) -and \
    -not -path '*\.svn*' |
  while read F
  do
    egrep -- '-ffree-form|LHpdflib.F' "$F" > /dev/null
    if [ $? == 0 ]; then
      echo -n "Fixing $F..."
      sed -i '' 's/-ffree-form//' "$F"
      sed -i '' 's/LHpdflib\.F/LHpdflib\.f90/' "$F"
      echo "done"
    fi
  done

  # Create the proper symbolic links
  find "$1/LHAPDF" -name "LHpdflib.F" |
  while read F
  do
    DEST="`dirname $F`/LHpdflib.f90"
    echo -n "Creating symlink $DEST..."
    ln -nfs "$F" "$DEST"
    echo "done"
  done

}

# Fix ROOT?
if [ "$1" == "--root" ]; then
  if [ -d "$ROOTSYS" ]; then
    FixCommon "$ROOTSYS"
  else
    echo "Set \$ROOTSYS to fix ROOT installation." >&2
  fi
# Fix AliRoot?
elif [ "$1" == "--aliroot" ]; then
  if [ -d "$ALICE_ROOT" ]; then
    FixCommon "$ALICE_ROOT"
    FixAliRoot "$ALICE_ROOT"
  else
    echo "Set \$ALICE_ROOT to fix AliRoot installation." >&2
  fi
else
  echo "Usage: $0 [--root|--aliroot]"
  exit 1
fi

echo "*** Use \"svn revert\" to restore modified files ***"
