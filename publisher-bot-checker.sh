#!/bin/bash

# Check if today's analysis tag is available on CVMFS and AliEn. Always send a
# Slack notification, send an email only if something's wrong.

source "$(echo "$0" | sed -e 's|\.sh$|.config|')" || exit 3

CVMFS_PREFIX=/cvmfs/alice.cern.ch/x86_64-2.6-gnu-4.1.2/Packages/AliPhysics
TODAYS_TAG=$(env TZ=Europe/Zurich LANG=C date --date=now +vAN-%Y%m%d)
CVMFS_PATH=$(ls -d $CVMFS_PREFIX/$TODAYS_TAG* 2> /dev/null | sort -n | tail -n1)
ALIEN_NAME=$(curl -sL http://alimonitor.cern.ch/packages/ | tac | \
             grep -m1 -o -E "VO_ALICE@AliPhysics::${TODAYS_TAG}-[0-9]+" | head -n1)

SLACK_MSG="Daily AliPhysics tag *$TODAYS_TAG* is"
[[ "$CVMFS_PATH" == '' ]] \
  && SLACK_MSG="$SLACK_MSG not available on CVMFS (expected at \`$CVMFS_PREFIX/$TODAYS_TAG*\`)" \
  || SLACK_MSG="$SLACK_MSG available on CVMFS at \`$CVMFS_PATH\`"
[[ "$ALIEN_NAME" == '' ]] \
  && SLACK_MSG="$SLACK_MSG and not available on AliEn" \
  || SLACK_MSG="$SLACK_MSG and available on AliEn as \`$ALIEN_NAME\`"

if [[ "$CVMFS_PATH" == '' || "$ALIEN_NAME" == '' ]]; then
  SLACK_MSG="$SLACK_MSG :scream:"
  echo "$SLACK_MSG" | mailx -r publisher-bot \
                            -s "[publisher-bot] $TODAYS_TAG still not available" \
                            root
else
  SLACK_MSG="All OK! $SLACK_MSG :thumbsup:"
fi

PAYLOAD=$(cat <<EOF
payload={ "channel": "$SLACK_CHANNEL",
          "username": "publisher-bot",
          "text": "$SLACK_MSG" }
EOF
)

curl -L -X POST \
     --silent \
     --data "$PAYLOAD" \
     "$SLACK_URL" > /dev/null
