#!/bin/bash -e

ARCH="$(basename "$PWD")"

MKDIR=mkdir
TOUCH=touch
LN=ln
MV=mv
TAR=tar
RM=rm

DRY="echo >>> DRY RUN >>> "
PACKS=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)
      MKDIR="$DRY $MKDIR"
      TOUCH="$DRY $TOUCH"
      LN="$DRY $LN"
      MV="$DRY $MV"
      TAR="$DRY $TAR"
      RM="$DRY $RM"
      shift
    ;;
    --fill)
      FILL=1
      shift
    ;;
    --)
      shift
      break
    ;;
    -*)
      echo "Unrecognized option: $1"
      false
    ;;
    *)
      break
    ;;
  esac
done

PACKS=("$@")

echo "This script will create the following dummy releases for arch $ARCH in directory $PWD:"
for P in "${PACKS[@]}"; do
  echo "  $P"
done

read -p "Type PROCEED (respect case) to proceed: " ANS
[[ "$ANS" == PROCEED ]]

for R in "${PACKS[@]}"; do
  PKGNAME=${R%%/*}
  PKGFULLVER=${R#*/}
  PKGVER=${PKGFULLVER%-*}

  PKGFINALREL=${PKGFULLVER##*-}
  PKGSTARTREL=$PKGFINALREL

  [[ "$FILL" == 1 ]] && PKGSTARTREL=1 || true

  for PKGREL in $(seq $PKGSTARTREL $PKGFINALREL); do
    # Per build number
    PKGFULLVER="$PKGVER-$PKGREL"

    # Exists already? Skip.
    if [[ -e dist/$PKGNAME/$PKGNAME-$PKGFULLVER ]]; then
      echo "$PKGNAME $PKGFULLVER: skipped"
      continue
    fi

    # This hash uniquely represents dummy packages.
    STORE="store/aa/aa10b02871075d3156ec8675dfc95b7d5d640aa6/$PKGNAME-$PKGFULLVER.$ARCH.tar.gz"
    TMPD=$(mktemp -d /tmp/dummy-XXXXX)
    pushd $TMPD > /dev/null
      $MKDIR -p content/$ARCH/$PKGNAME/$PKGFULLVER
      echo "This is a placeholder package for $PKGNAME $PKGFULLVER $ARCH" > content/$ARCH/$PKGNAME/$PKGFULLVER/README
      $TAR -C content -czf $TMPD/$PKGNAME-$PKGFULLVER.$ARCH.tar.gz ./
    popd > /dev/null
    $MKDIR -p $(dirname $STORE)
    $MV $TMPD/$PKGNAME-$PKGFULLVER.$ARCH.tar.gz $STORE
    $RM -rf $TMPD
    $MKDIR -p dist/$PKGNAME/$PKGNAME-$PKGFULLVER
    $MKDIR -p dist-runtime/$PKGNAME/$PKGNAME-$PKGFULLVER
    $MKDIR -p dist-direct/$PKGNAME/$PKGNAME-$PKGFULLVER
    $LN -nfs ../../../../../TARS/$ARCH/$STORE \
             dist/$PKGNAME/$PKGNAME-$PKGFULLVER/$PKGNAME-$PKGFULLVER.$ARCH.tar.gz
    $LN -nfs ../../../../../TARS/$ARCH/$STORE \
             dist-runtime/$PKGNAME/$PKGNAME-$PKGFULLVER/$PKGNAME-$PKGFULLVER.$ARCH.tar.gz
    $LN -nfs ../../../../../TARS/$ARCH/$STORE \
             dist-direct/$PKGNAME/$PKGNAME-$PKGFULLVER/$PKGNAME-$PKGFULLVER.$ARCH.tar.gz
    $MKDIR -p $PKGNAME
    $LN -nfs ../../$ARCH/$STORE $PKGNAME/$PKGNAME-$PKGFULLVER.$ARCH.tar.gz
    echo $PKGNAME $PKGFULLVER OK
  done

done

#./dist/AliEn-CAs
#./dist/AliEn-CAs/AliEn-CAs-v1-1
#./dist/AliEn-CAs/AliEn-CAs-v1-1/AliEn-CAs-v1-1.slc5_x86-64.tar.gz
#./AliEn-CAs
#./AliEn-CAs/AliEn-CAs-v1-1.slc5_x86-64.tar.gz
#./dist-direct/AliEn-CAs
#./dist-direct/AliEn-CAs/AliEn-CAs-v1-1
#./dist-direct/AliEn-CAs/AliEn-CAs-v1-1/AliEn-CAs-v1-1.slc5_x86-64.tar.gz
#./dist-runtime/AliEn-CAs
#./dist-runtime/AliEn-CAs/AliEn-CAs-v1-1
#./dist-runtime/AliEn-CAs/AliEn-CAs-v1-1/AliEn-CAs-v1-1.slc5_x86-64.tar.gz
#./store/12/12582d3c3f8e80e636da3183431759ebf892654f/AliEn-CAs-v1-1.slc5_x86-64.tar.gz
