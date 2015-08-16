#!/bin/bash
# Send an email if AliPhysics is not yet on CVMFS. Use in crontab at ~18.30
Pref='/cvmfs/alice.cern.ch/x86_64-2.6-gnu-4.1.2/Packages/AliPhysics'
AnTag=`env TZ=Europe/Zurich LANG=C date --date='now' +vAN-%Y%m%d`
[[ -d $Pref/$AnTag ]] && exit 0
cat | mailx -r cvmfs-checker \
            -s "[CVMFS Checker] $AnTag still not available" \
            root <<EoF
Today's AliPhysics tag ($AnTag) is not available on CVMFS:

  $Pref/$AnTag

Please check.
--
CVMFS Checker
EoF
