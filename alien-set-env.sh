#!/bin/bash

#
# alien-set-env.sh -- by Dario Berzano <dario.berzano@gmail.com>
#
# Sets the environment for AliEn, allowing the user to choose among different
# versions installed under the same base directory.
#

# This is the only variable to set: path to the directory that contains the
# alien and alien.vXXXXX directories.
export ALIEN_PREF="/opt/alisw"

declare -a ALIEN_VERSIONS
export ALIEN_COUNT=0
export ALIEN_TEMP=`mktemp /tmp/alien_chooser_XXXXXX`
export ALIEN_VER
export R

ls -1d "$ALIEN_PREF/alien."* 2>/dev/null > $ALIEN_TEMP
if [ $? != 0 ]; then
  echo "No AliEn versions available."
  rm $ALIEN_TEMP
  return
fi

echo -n "AliEn versions: "

while read R
do
 ALIEN_VER=`echo $R | perl -ne '/alien\.(.*)$/; print "$1\n"'`
 ALIEN_VERSIONS[$ALIEN_COUNT]=$ALIEN_VER
 let ALIEN_COUNT++
 echo -ne "\033[1;36m($ALIEN_COUNT)\033[1;35m$ALIEN_VER "
done < $ALIEN_TEMP

echo -e "\033[m"

rm $ALIEN_TEMP

R=0
while [ "$R" == "" ] || [ "$R" -lt 1 ] || [ "$R" -gt $ALIEN_COUNT ]
do
  echo -n "Choose one: "
  read R
  R=`expr $R + 0 2> /dev/null`
done

let R--
ALIEN_VER=${ALIEN_VERSIONS[$R]}
export LD_LIBRARY_PATH="$ALIEN_PREF/alien.$ALIEN_VER/lib:$ALIEN_PREF/alien.$ALIEN_VER/api/lib:$LD_LIBRARY_PATH"
export PATH="$ALIEN_PREF/alien.$ALIEN_VER/bin:$ALIEN_PREF/alien.$ALIEN_VER/api/bin:$PATH"
ln -nfs "$ALIEN_PREF/alien.$ALIEN_VER" "$ALIEN_PREF/alien"

echo -e "Version \033[1;35m$ALIEN_VER\033[m set."

unset ALIEN_PREF ALIEN_VERSIONS ALIEN_COUNT ALIEN_TEMP ALIEN_VER R
