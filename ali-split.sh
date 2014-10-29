#!/bin/bash

#
# ali-split.sh -- by Dario Berzano & Alina Grigoras
#
# tools to split the AliRoot Git repository in two
#


# a print function with colors, on stderr
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
  echo -e "${selcol}$2${nocol}" >&2
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

# list all files ever written in all remote branches, also the ones not
# currently present in the working directory, also the ones that have
# been deleted
function lsallfiles() (

  # list what changed in revision <rev> (wrt/the previous)
  #   git diff-tree --no-commit-id --name-only -r <rev>
  # if run on every commit, it will produce eventually the full list
  # of files ever written! note that this is much faster than using
  # git ls-files

  # list all commits for a branch (no need to check it out)
  #   git rev-list <branch>

  # list all commits in all remote branches
  #   git rev-list --remotes

  regexp="$1"
  invert_regexp="$2"
  only_root_dir="$3"

  prc yellow 'listing all files ever written to Git history in all branches'
  if [[ $regexp != '' ]] ; then
    prc magenta "showing only entries matching extended regexp: $regexp"
    [[ ${invert_regexp} == 1 ]] && prc magenta 'inverting regexp match'
    [[ ${only_root_dir} == 1 ]] && prc magenta 'printing only list of dirs under root'
  fi

  fatal cd "$GitRootSplit"

  [[ $invert_regexp == 1 ]] && invert_regexp='-v'

  git rev-list --remotes | while read commit ; do
    git diff-tree --no-commit-id --name-only -r $commit | \

      if [[ "$regexp" != '' ]] ; then
        grep $invert_regexp -E "$regexp"
      else
        cat
      fi | \

      if [[ $only_root_dir == 1 ]] ; then
        grep -oE '^([^/]*)/'
      else
        cat
      fi

  done | sort -u

)

# nice time formatting
function nicetime() (
  t=$1
  hr=$(( t / 3600 ))
  t=$(( t % 3600 ))
  mn=$(( t / 60 ))
  t=$(( t % 60 ))
  sc=$t
  echo "${hr}h ${mn}m ${sc}s"
)

# the main function
function main() (

  while [[ $# -gt 0 ]] ; do
    case "$1" in
      --source)
        GitRootSplit="$2"
        shift
      ;;
      --regexp)
        RegExp="$2"
        shift
      ;;
      --invert-match)
        RegExpInvert=1
      ;;
      --only-root-dir)
        OnlyRootDir=1
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
      lsallfiles)
        do_lsallfiles=1
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

  # process actions in right order, and time them
  ts_start=$( date --utc +%s )
  [[ $do_updbr == 1 ]] && updbr
  [[ $do_listbr == 1 ]] && listbr
  [[ $do_cleanall == 1 ]] && cleanall
  [[ $do_dirlist == 1 ]] && dirlist
  [[ $do_lsallfiles == 1 ]] && lsallfiles "$RegExp" "$RegExpInvert" "$OnlyRootDir"
  ts_end=$( date --utc +%s )
  ts_delta=$(( ts_end - ts_start ))

  prc magenta "time taken by all operations: $( nicetime $ts_delta )"

)

# entry point
main "$@"
