#!/bin/bash -e

function _git_sync() (
  git remote update -p && git fetch && git fetch --tags
)

TmpDir="/tmp"
CurDir="$( dirname "$0" )"
CurDir=$( cd "$CurDir" ; pwd )

DontCopy="$2"

if [[ $1 =~ ^(.*-)([0-9]+)$ ]]; then

  prev=$( printf %02d $(( ${BASH_REMATCH[2]} - 1 )) )

  AliRootNew="$1"
  AliRootOld="${BASH_REMATCH[1]}${prev}"

  AliPhysicsNew="${AliRootNew}-01"
  AliPhysicsOld="${AliRootOld}-01"

else
  echo "Version number not recognized: \"$1\". Use something like: v5-06-34"
  exit 1
fi

cd $ALICE_ROOT/../src
_git_sync
"$CurDir"/git-changeset.sh --sw AliRoot --old $AliRootOld --new $AliRootNew --format html > "$TmpDir"/text.$AliPhysicsNew

echo '' >> "$TmpDir"/text.$AliPhysicsNew

cd $ALICE_PHYSICS/../src
_git_sync
"$CurDir"/git-changeset.sh --sw AliPhysics --old $AliPhysicsOld --new $AliPhysicsNew --format html >> "$TmpDir"/text.$AliPhysicsNew

echo "AliRoot ${AliRootNew} is on the Grid. Please wait for AliPhysics ${AliPhysicsNew} to be available." > "$TmpDir"/text.$AliRootNew
echo 'dario.berzano@cern.ch;peter.hristov@cern.ch' > "$TmpDir"/emails.$AliRootNew

echo 'latchezar.betev@cern.ch;yves.roland.schutz@cern.ch;andreas.morsch@cern.ch;matthias.richter@cern.ch;mihaela.gheata@cern.ch;chiara.zampolli@cern.ch;sylvain.chapeland@cern.ch;barthelemy.von.haller@cern.ch;jochen@thaeder.de;raffaele.grosso@cern.ch;d.miskowiec@gsi.de;mploskon@lbl.gov;adriana.telesca@cern.ch;peter.hristov@cern.ch;predrag.buncic@cern.ch;cvetan.cheshkov@cern.ch;ahmed.soudi@cern.ch;catalin.ristea@cern.ch;dario.berzano@cern.ch;michal.broz@cern.ch;alice-analysis-operations@cern.ch' > "$TmpDir"/emails.$AliPhysicsNew

cd "$TmpDir"
if [[ "$DontCopy" == '--no-copy' ]] ; then
  for f in text.$AliRootNew text.$AliPhysicsNew emails.$AliRootNew emails.$AliPhysicsNew; do
    echo "==> $f <=="
    cat "$f" | pygmentize -lhtml
    echo ''
  done
else
  scp text.$AliRootNew text.$AliPhysicsNew \
      emails.$AliRootNew emails.$AliPhysicsNew \
      aliroot@alirootbuild3.cern.ch:/packages_spool/
fi

echo all ok
rm -f text.$AliRootNew text.$AliPhysicsNew emails.$AliRootNew emails.$AliPhysicsNew
