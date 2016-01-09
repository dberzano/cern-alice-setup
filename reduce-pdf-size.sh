#!/bin/bash
while [[ $# -gt 0 ]]; do
  case "$1" in
    --smaller) PDFSETTINGS=/screen ; shift ;;
    --small)   PDFSETTINGS=/ebook  ; shift ;;
    --replace) REPLACE=1           ; shift ;;
    --) shift ; break ;;
    -*) echo "Option not recognized: $1" ; exit 1 ;;
    *) break ;;
  esac
done
if [[ "$PDFSETTINGS" == '' ]]; then
  echo "Please use --smaller or --small."
  exit 1
fi
STAT='stat -f%z'
TMP=$(mktemp /tmp/stat-XXXXX)
$STAT $TMP > /dev/null 2>&1 || STAT='stat -c%s'
while [[ $# -gt 0 ]]; do
  FILE="$1"
  EXT=${FILE##*.}
  BASE=${FILE%.*}
  DEST_FILE="${BASE}_reduced.${EXT}"
  ORIG_FILE="${BASE}_original.${EXT}"
  echo -n "Processing ${FILE}: "
  gs -sDEVICE=pdfwrite \
     -dCompatibilityLevel=1.4 \
     -dPDFSETTINGS=$PDFSETTINGS \
     -dNOPAUSE \
     -dQUIET \
     -dBATCH \
     -sOutputFile="$DEST_FILE" \
     "$FILE" > /dev/null 2>&1
  if [[ $? == 0 ]]; then
    if [[ $REPLACE == 1 ]]; then
      mv "$FILE" "$ORIG_FILE"
      mv "$DEST_FILE" "$FILE"
      DEST_FILE="$FILE"
      echo -n "OK, backed up to $ORIG_FILE"
    else
      echo -n "OK, written $DEST_FILE"
      ORIG_FILE="$FILE"
    fi
    ORIG_SIZE=$($STAT "$ORIG_FILE")
    DEST_SIZE=$($STAT "$DEST_FILE")
    PCT=$(echo "scale=1; 100*$DEST_SIZE/$ORIG_SIZE" | bc)
    echo " - size: $ORIG_SIZE -> $DEST_SIZE (${PCT}%)"
  else
    echo "failed"
  fi
  shift
done
