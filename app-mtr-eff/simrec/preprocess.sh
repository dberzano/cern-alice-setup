#!/bin/bash

#
# Functions
#

# The main function
function Main() {

  local FILE="$1"
  local T1=$(mktemp /tmp/preprocess-XXXXXX)
  local T2=$(mktemp /tmp/preprocess-XXXXXX)
  shift

  cp "$FILE" "$T1"

  while [ $# -ge 2 ]; do
    #echo $1=$2
    sed -e 's/@'"$1"'@/'"$2"'/g' "$T1" > "$T2"
    cp "$T2" "$T1"
    shift 2
  done

  cat "$T1"
  rm -f "$T1" "$T2"
}

#
# Entry point
#

Main "$@"



#sed -e 's/@prova@/prova=prova/' cosa.txt
