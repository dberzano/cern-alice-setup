#!/bin/bash

cd `dirname "$0"`

function mktmpdir() {
  [ -z "$TMPDIR" ] && mktemp -d || mktemp -d "$TMPDIR/par.XXXXX"
}

ShowSkip=0
while [ $# -gt 0 ] ; do
  case "$1" in
    --show-skipped) ShowSkip=1 ;;
    --proof-packages-dir) PackagesDir="$2" ; shift ;;
  esac
  shift
done

if [ -z "$PackagesDir" ] ; then
  echo "What is the PROOF packages directory?"
  echo "  $0 --proof-packages-dir /the/proof/dir/for/packages"
  exit 1
fi

export CountDone=0
export CountSkip=0

mkdir -p "$PackagesDir" 2> /dev/null
if [ ! -d "$PackagesDir" ] ; then
  echo "Cannot create packages directory: $PackagesDir"
  exit 2
fi
PackagesDir=`cd "$PackagesDir";pwd`

source /cvmfs/alice.cern.ch/etc/login.sh
if [ $? != 0 ] ; then
  echo "Cannot load ALICE environment. Check CVMFS setup."
  exit 3
fi

while read AliRootVer ; do

  if [ -e "$PackagesDir/$AliRootVer.par" ] && [ -d "$PackagesDir/$AliRootVer" ] ; then
    [ $ShowSkip == 1 ] && echo -e "[\033[34m skip \033[m] $AliRootVer"
    let CountSkip++
    continue
  fi

  echo -n "[ .... ] $AliRootVer"

  T=`mktmpdir`

  (
    mkdir -p "$T/$AliRootVer/PROOF-INF"
    cp AliRoot_SETUP.C "$T/$AliRootVer/PROOF-INF/SETUP.C"
    tar -C "$T" --force-local -czvvf "$PackagesDir/$AliRootVer.par" "$AliRootVer/"
    tar -C "$PackagesDir" --force-local -xzvvf "$PackagesDir/$AliRootVer.par"
  ) > $T/log.txt 2>&1

  if [ -e "$PackagesDir/$AliRootVer.par" ] && [ -d "$PackagesDir/$AliRootVer" ] ; then
    echo -e "\r[\033[32m  OK  \033[m]"
    let CountDone++
  else
    echo -e "\r[\033[31m fail \033[m]"
    echo "*** LOG FOLLOWS ***"
    cat $T/log.txt
    rm -rf "$T"
    break
  fi

  rm -rf "$T"

done < <( alienv q | grep '^VO_ALICE@AliRoot::' )

echo "$CountDone package(s) created"
echo "$CountSkip package(s) were already up-to-date"
