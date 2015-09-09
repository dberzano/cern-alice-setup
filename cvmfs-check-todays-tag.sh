#!/bin/bash

# Send an email if AliPhysics is not yet on CVMFS. Use in crontab at ~18.30.
# Always send a Slack notification.

source "$(echo "$0" | sed -e 's|\.sh$|.config|')" || exit 3
Pref='/cvmfs/alice.cern.ch/x86_64-2.6-gnu-4.1.2/Packages/AliPhysics'
AnTag=`env TZ=Europe/Zurich LANG=C date --date='now' +vAN-%Y%m%d`
FullPath=$(ls -d $Pref/$AnTag* | sort -n | tail -n1)
if [[ "$FullPath" != "" ]]; then
  echo "OK: $FullPath" >&2
  SlackMsg="Today's AliPhysics tag *$AnTag* is available on CVMFS :thumbsup:"
  SlackColor="good"
  rv=0
else
  echo "Not OK, sending mail: $AnTag" >&2
  mailx -r cvmfs-checker \
              -s "[CVMFS Checker] $AnTag still not available" \
              root <<EoF
Today's AliPhysics tag ($AnTag) is not available on CVMFS:

  $Pref/$AnTag*

Please check.
--
CVMFS Checker
EoF
  SlackMsg="Today's AliPhysics tag *$AnTag* is not yet available on CVMFS :scream: Could you please have a look?"
  SlackColor="danger"
  rv=2
fi

SlackPayload=$(cat <<EoF
payload={
  "channel": "$SlackChannel",
  "username": "cvmfs-checker",
  "text": "$SlackMsg",
  "attachments": [{
    "pretext": "Path:",
    "text": "\`$FullPath\`",
    "color": "$SlackColor",
    "mrkdwn_in": [ "text" ]
   }]
}
EoF
)

curl -L -X POST \
     --silent \
     --data "$SlackPayload" \
     "$SlackUrl" > /dev/null

exit $rv
