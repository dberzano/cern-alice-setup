#!/bin/bash

#
# fix-tags.sh -- by Dario Berzano and Alina Grigoras
#
# See README.md for a description.
#

perr() {
  echo -e "\033[31m$1\033[m" >&2
}

pinf() {
  echo -e "\033[34m$1\033[m" >&2
}

[ "$1" == '--fix' ] && fix=1

git config user.name 'dberzano'
git config user.email 'dario.berzano@cern.ch'

pinf 'listing all tags with (no author)'
[ "$fix" != 1 ] && perr 'to fix them, use --fix'

git tag | while read tag ; do
  tagfile=$( git cat-file tag "$tag" 2>&1 )
  if [ $? != 0 ] ; then
    perr "invalid: $tag, skipping"
  else
    ref=$( echo "$tagfile" | grep '(no author)' -C 10 | grep '^object' | awk '{ print $2 }' )
    if [ "$ref" != '' ] ; then
      pinf "$ref <- $tag"
      if [ "$fix" == 1 ] ; then
        git tag -d "$tag" || exit 1
        git tag -a "${tag}" -m 'Retagging to fix missing author' "$ref" || exit 1
        git push origin ":refs/tags/${tag}" || exit 1  # to be improved
      fi
    fi
  fi
done

# to be improved
git push --tags
