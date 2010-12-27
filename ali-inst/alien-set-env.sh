#!/bin/bash

export ALIEN_PREF="/opt/alisw"
declare -a ALIEN_VERSIONS
export ALIEN_COUNT=0
export ALIEN_TEMP=`mktemp /tmp/alien_chooser_XXXXXX`
export ALIEN_VER
export R

ls -1d $ALIEN_PREF/alien.* > $ALIEN_TEMP

echo -n "AliEn versions: "

while read R
do
 ALIEN_VER=`echo $R | perl -ne '/alien\.(.*)$/; print "$1\n"'`
 ALIEN_VERSIONS[$ALIEN_COUNT]=$ALIEN_VER
 let ALIEN_COUNT++
 echo -n "($ALIEN_COUNT)$ALIEN_VER "
done < $ALIEN_TEMP

echo ""

rm $ALIEN_TEMP

R=0
while [ $R -lt 1 ] || [ $R -gt $ALIEN_COUNT ]
do
  echo -n "Choose one: "
  read R
done

let R--
ALIEN_VER=${ALIEN_VERSIONS[$R]}
export LD_LIBRARY_PATH=$ALIEN_PREF/alien.$ALIEN_VER/lib:$ALIEN_PREF/alien.$ALIEN_VER/api/lib:$LD_LIBRARY_PATH
export PATH=$ALIEN_PREF/alien.$ALIEN_VER/bin:$ALIEN_PREF/alien.$ALIEN_VER/api/bin:$PATH

unset ALIEN_PREF ALIEN_VERSIONS ALIEN_COUNT ALIEN_TEMP ALIEN_VER R
