#!/bin/bash

# PORCO DIO LORDO

if [ "$1" == "" ]; then
  echo "Usage: $0 [file1.dat [file2.dat...]]"
  exit 1
fi

for F in "$@"
do
  BN=${F%.*}
  RN="$BN.root"
  aliroot -q ../macros/MUONConvertTrigBoardEff.C'("'"${F}"'", "'"${RN}"'")'
  aliroot -q $ALICE_ROOT/MUON/MUONTriggerChamberEfficiency.C'("'"${RN}"'", "local://./cdb/'"${BN}"'")'
done

# List all the fucking produced OCDB files
echo ""
echo "==== What's inside the CDB directory? ===="
find cdb -name '*.root' -exec ls -l '{}' \;
