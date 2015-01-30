#!/bin/bash
cd "$(dirname "$0")"

# exit on first error
set -e

# echo every shell command
#set -x

#what='aliroot'
what='aliphysics'

parname=$1
if [[ $parname == '' ]] ; then
  parname='FOO'
  modpath='FOO'
else
  modpath=$2
  [[ $modpath == '' ]] && modpath=$parname
fi

cd "$ALICE_PREFIX"

if [[ $what == 'aliroot' ]] ; then
  cd aliroot/master
  rm -rf inst/PARfiles/
  rm -rf build/${modpath}/*
  mkdir -p build
  cd build
  cmake ../src/ -DALIEN=$ALIEN_DIR -DROOTSYS=$ROOTSYS -DCMAKE_INSTALL_PREFIX=$(cd ..;pwd)/inst
else
  cd aliphysics/master
  rm -rf inst/PARfiles/
  rm -rf build/${modpath}/*
  mkdir -p build
  cd build
  cmake ../src \
  -DCMAKE_INSTALL_PREFIX="$ALICE_PHYSICS" \
  -DCMAKE_C_COMPILER=`root-config --cc` \
  -DCMAKE_CXX_COMPILER=`root-config --cxx` \
  -DCMAKE_Fortran_COMPILER=`root-config --f77` \
  -DALIEN="$ALIEN_DIR" \
  -DROOTSYS="$ROOTSYS" \
  -DFASTJET="$FASTJET" \
  -DALIROOT="$ALICE_ROOT"
fi

# make the parfile
make ${parname}.par

# we are inside build (for either aliroot or aliphysics)
make -j$MJ install

# go in the parfiles dest
cd ../inst/PARfiles

# list content of PARfile
tar tvvf ${parname}.par

cat > /tmp/test${parname}Par.C <<EOF
void test${parname}Par() {
  TProof::Open("workers=1");
  gProof->UploadPackage("${PWD}/${parname}.par");
  gProof->EnablePackage("${parname}");
}
EOF

# save current path, cd to root
CurPath=$PWD
cd /

# cleanup proof packages
rm -rf ${HOME}/.proof
#rm -rf ${HOME}/.proof/packages/

# start root
root -l -b /tmp/test${parname}Par.C
r=$?

# cleanup, preserve root exit code
rm -f /tmp/test${parname}Par.C
exit $r
