#!/bin/bash

#
# ali-split.sh -- by Dario Berzano & Alina Grigoras
#
# tools to split the AliRoot Git repository in two
#


# a print function with colors
function prc() (
  declare -A color
  color=(
    [red]="\033[31m"
    [yellow]="\033[33m"
    [green]="\033[32m"
    [blue]="\033[34m"
    [magenta]="\033[35m"
    [hi]="\033[1m"
  )
  selcol=${color[$1]:=${color[hi]}}
  nocol="\033[m"
  echo -e "${selcol}$2${nocol}"
)

# a print function
function pr() (
  prc hi "$1"
)

# break if something is wrong
function fatal() {
  "$@"
  local rv=$?
  if [[ $rv != 0 ]] ; then
    prc red "this should not happen, aborting:"
    prc red "  $@ --> returned $rv"
    exit 10
  fi
}

# update remote branches
function updbr() (
  fatal cd "$ALICE_ROOT"
  prc yellow 'updating list of remote branches'
  fatal git remote update --prune
)

# list remote branches
function listbr() (

  # the git plumbing interface (to be used in scripts):
  # https://www.kernel.org/pub/software/scm/git/docs/git.html#_low_level_commands_plumbing

  fatal cd "$ALICE_ROOT"

  prc yellow "listing all available remote branches"

  # produce lines to be either piped in shell, or eval'd
  # the %(var) is correctly escaped
  # this one produces one line per *remote* branch.
  # assumption: our remote is called "origin"
  git for-each-ref --shell \
    --format 'echo %(refname)' \
    refs/remotes/origin/ | \
    while read Line ; do
      if [[ $(eval "$Line") =~ ^refs/remotes/origin/(.*)$ ]] ; then
        pr ${BASH_REMATCH[1]}
      else
        prc red "should not happen, aborting: $Line"
        exit 10
      fi
    done

)

# the main function
function main() (

  if [[ ! -d "$ALICE_ROOT/.git" ]] ; then
    prc red 'set the $ALICE_ROOT var to the original AliRoot source dir'
    return 1
  fi

  prc yellow "working on AliRoot source on: $ALICE_ROOT"

  while [[ $# -gt 0 ]] ; do
    case "$1" in
      listbr)
        do_listbr=1
      ;;
      updbr)
        do_updbr=1
      ;;
      *)
        prc red "not understood: $1"
        return 1
      ;;
    esac
    shift
  done

  # process actions in right order
  [[ $do_updbr == 1 ]] && updbr
  [[ $do_listbr == 1 ]] && listbr

)

# entry point
main "$@"
