#/bin/bash

# Print a list of changes between two Git refs, formatted

Format=''

while [[ $# -gt 0 ]] ; do
  [[ "${1:0:2}" != '--' ]] && break
  case "$1" in
    --format)
      Format="$2"
      shift
    ;;
    --sw)
      Sw="$2"
      shift
    ;;
    --old)
      CommitOld="$2"
      shift
    ;;
    --new)
      CommitNew="$2"
      shift
    ;;
  esac
  shift
done

Sw=${Sw:-AliRoot}
BaseUrl="http://git.cern.ch/pubweb/${Sw}.git/commit"

[[ "$CommitNew" == '' || "$CommitOld" == '' ]] && exit 0

case "$Format" in
  html)
    function Link()   ( echo "<a href=\"$1\">$2</a>" )
    function Bold()   ( echo "<b>$1</b>" )
    function Italic() ( echo "<i>$1</i>" )
    function List()   ( echo "<ul>$1</ul>" )
    function Item()   ( echo "<li>$1</li>" )
    function Par()    ( echo "<p>$1</p>" )
  ;;

  jira)
    function Link()   ( echo -e "[$2|$1]" )
    function Bold()   ( echo -e "*$1*" )
    function Italic() ( echo -e "_$1_" )
    function List()   ( echo -e "$1\n" )
    function Item()   ( echo -e "* $1" )
    function Par()    ( echo -e "$1\n" )
  ;;

  *)
    function Link()   ( echo -e "$2" )
    function Bold()   ( echo -e "\033[1m$1\033[m" )
    function Italic() ( echo -e "\033[36m$1\033[m" )
    function List()   ( echo -e "$1" )
    function Item()   ( echo -e " \033[35m*\033[m $1" )
    function Par()    ( echo -e "$1\n" )
  ;;

esac

# See http://git-scm.com/docs/git-log
GitLogFormat="`Link "${BaseUrl}/%H" "%h"`: %s `Italic "(%an)"`"
GitLogFormat="`Item "$GitLogFormat"`"

(
  Par "New ${Sw} release `Bold "${CommitNew}"`. Changeset with respect to `Bold "${CommitOld}"`:"
  List "$( git log --pretty=format:"$GitLogFormat" "$CommitNew"..."$CommitOld" )"
)
