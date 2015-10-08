#/bin/bash
cd $ALICE_PREFIX/alien
#DRY=false
while read EXE; do
  EXE=${EXE%%:*}
  LIBID=$(otool -D "$EXE" | grep -vE ':$')

  # Fix library ID.
  if [[ "$LIBID" != '' && "${LIBID:0:1}" != / ]]; then
    FULLLIB=$(cd "$(dirname "$EXE")"; pwd)/$(basename "$LIBID")
    echo "INFO: $EXE: setting lib ID to $FULLLIB"
    $DRY install_name_tool -id "$FULLLIB" \
                      "$EXE"
  fi

  while read PROBLIB; do
    FULLIB=
    for LIBPATH in $PWD/lib $PWD/api/lib; do
      if [[ -e "$LIBPATH/$PROBLIB" ]]; then
        FULLLIB=$LIBPATH/$PROBLIB
        break
      fi
    done
    if [[ "$FULLLIB" == '' ]]; then
      echo "WARNING: $EXE: cannot locate $P" >&2
    else
      echo "INFO: $EXE: $PROBLIB -> $FULLLIB"
      $DRY install_name_tool -change "$PROBLIB" "$FULLLIB" \
                        "$EXE"
    fi
  done < <(otool -L $EXE | grep -E '\tlib' | awk '{print $1}')
done < <(
  find -E . \
          \( -perm -700 -or -perm -770 -or -perm -707 -or -perm -777 \) \
          -and -type f \
          -and -regex ".*/(lib(64)?|bin)/.*" \
          -exec file '{}' \; | grep -iE 'macha-o|64|32|386|shared library'
)
