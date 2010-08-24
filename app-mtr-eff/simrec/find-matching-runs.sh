#!/bin/bash

declare -a JOBS
#JOBS=( sim-realistic-r-maxcorr sim-realistic-50pct-maxcorr sim-realistic-75pct-maxcorr sim-realistic-fulleff )
JOBS=( sim-realistic-75pct-maxcorr sim-realistic-fulleff )

export PREFIX="/dalice05/berzano/jobs"
export MAXRUNS=100
export NJOBS=${#JOBS[@]}
export LISTNAME="partial_matching.txt"
export COUNT
export VERB=0

if [ "$1" == "-v" ]; then
  VERB=1
elif [ "$1" == "-vv" ]; then
  VERB=2
fi

[ $VERB -ge 1 ] && echo -e "\033[1;33mPlain text lists will be written in:\033[m"
for J in ${JOBS[@]}
do
  LISTNAMEFULL=$PREFIX/$J/$LISTNAME
  rm -f $LISTNAMEFULL
  [ $VERB -ge 1 ] && echo -e "\033[1;33m>>\033[m $LISTNAMEFULL"
done

for ((I=0; $I<$MAXRUNS; I++))
do
  COUNT=0
  declare -a FOUND
  for J in ${JOBS[@]}
  do
    REALDIR=$(ls -1d $PREFIX/$J/*0$I 2> /dev/null)
    if [ "$REALDIR" != "" ]; then
      if [ -e "$REALDIR/AliESDs.root" ]; then
        FOUND[$COUNT]="$REALDIR/AliESDs.root"
        let COUNT++
      fi
    fi
  done

  if [ $COUNT == $NJOBS ]; then
    printf "Run %06d: \033[1;32mOK\033[m\n" $I
    COUNT=0
    for J in ${JOBS[@]}
    do
      LISTNAMEFULL=$PREFIX/$J/$LISTNAME
      echo "${FOUND[$COUNT]}" >> "$LISTNAMEFULL"
      let COUNT++
    done
  elif [ $COUNT -gt 0 ] && [ $VERB -ge 2 ]; then
    printf "Run %06d: \033[1;31mno match\033[m\n" $I
  fi

  unset FOUND
done
