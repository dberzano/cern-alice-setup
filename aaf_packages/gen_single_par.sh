#!/bin/bash

cd "$( dirname "$0" )"

if [[ $1 != '' ]] ; then
  parname=$1
else
  parname='AliRoot'
fi

src="${PWD}/AliRoot_SETUP.C"
dst="${PWD}/${parname}.par"
#dst='/Volumes/cloud-gw-218/Analyses/Leoncino/CENTRALITY/LHC13de/new_OADB/${parname}.par'

t=`mktemp -d /tmp/AliRoot_PAR-XXXXX`
mkdir -p "${t}/${parname}/PROOF-INF"
cp "$src" "${t}/${parname}/PROOF-INF/SETUP.C"
rm -f "$dst"
( cd "$t" && tar czf "$dst" "${parname}/" )

rm -rf "$t"

if [[ -e "$dst" ]] ; then
  echo -e "\033[32mparfile recreated at \033[35m${dst}\033[m"
else
  echo -e "\033[31cannot recreate parfile at \033[34m${dst}\033[m"
fi
