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
    prc red "  $* --> returned $rv"
    exit 10
  fi
}

# update remote branches
function updbr() (
  fatal cd "$GitRootSplit"
  prc yellow 'updating list of remote branches'
  fatal git remote update --prune
)

# list remote branches
function listbr() (

  # the git plumbing interface (to be used in scripts):
  # https://www.kernel.org/pub/software/scm/git/docs/git.html#_low_level_commands_plumbing

  fatal cd "$GitRootSplit"

  prc yellow "listing all available remote branches"

  # produce lines to be either piped in shell, or eval'd
  # the %(var) is correctly escaped
  # this one produces one line per *remote* branch.
  # assumption: our remote is called "origin"
  git for-each-ref --shell \
    --format 'echo %(refname)' \
    refs/remotes/origin/ | \
    while read Line ; do
      if [[ $(eval "$Line") =~ /([^/]*)$ ]] ; then
        pr ${BASH_REMATCH[1]}
      else
        prc red "should not happen, aborting: $Line"
        exit 10
      fi
    done

)

# cleans all: reverts all to a pristine state (just cloned)
function cleanall() (

  fatal cd "$GitRootSplit"
  prc yellow "cleaning all"

  # move to detached
  fatal git clean -f -d
  fatal git reset --hard HEAD
  fatal git checkout $(git rev-parse HEAD)

  # iterates over local branches (refs/heads/)
  git for-each-ref --shell \
    --format 'echo %(refname)' \
    refs/heads/ | \
    while read Line ; do
      if [[ $(eval "$Line") =~ /([^/]*)$ ]] ; then
        fatal git branch -D "${BASH_REMATCH[1]}"
      else
        prc red "should not happen, aborting: $Line"
        exit 10
      fi
    done

  # move to master
  fatal git checkout master
  fatal git clean -f -d
  fatal git reset --hard HEAD
  fatal git remote update --prune
  fatal git pull

  prc green "repository restored to a pristine and updated state: now it looks like a fresh clone :-)"

)

# the main function
function main() (

  while [[ $# -gt 0 ]] ; do
    case "$1" in
      --source)
        GitRootSplit="$2"
        shift
      ;;
      listbr)
        do_listbr=1
      ;;
      updbr)
        do_updbr=1
      ;;
      cleanall)
        do_cleanall=1
      ;;
      *)
        prc red "not understood: $1"
        return 1
      ;;
    esac
    shift
  done

  GitRootSplit=$( cd "$GitRootSplit" ; pwd )
  if [[ ! -d "$GitRootSplit/.git" ]] ; then
    prc red 'set the $GitRootSplit var to the original Git source dir'
    return 1
  fi

  export GitRootSplit
  prc yellow "working on Git source on: $GitRootSplit"

  # process actions in right order
  [[ $do_updbr == 1 ]] && updbr
  [[ $do_listbr == 1 ]] && listbr
  [[ $do_cleanall == 1 ]] && cleanall
  [[ $do_dirlist == 1 ]] && dirlist

)

# entry point
main "$@"
