#!/bin/bash

testWhat=${1:-push}
testCount=${2:-1}

testFile=test1.txt
testFile2=test2.txt
remote=bare
testBranch=my_test_branch

function test_commits() {
  local testCount=$1
  rm -f $testFile
  for i in `seq 1 $testCount`; do
    echo $RANDOM >> $testFile
    echo $RANDOM >> $testFile2
    git add -v $testFile $testFile2
    git commit -m "Automatic commit $i of $testCount

Note that this commit spans on multiple lines.
Just like this."
  done
}

function test_tags() {
  local testCount=$1
  local annotated=$2
  for i in `seq 1 $testCount`; do
    ( git push $remote :refs/tags/autoTag-$i
      git tag -d autoTag-$i ) > /dev/null 2>&1
    if [[ "$annotated" == 1 ]]; then
      git tag -a autoTag-$i -m "This is an annotated tag for autoTag-$i.
This tag spans on multiple lines."
    else
      git tag autoTag-$i
    fi
    git cat-file -t autoTag-$i
  done
}

case "$testWhat" in

  push)
    # Ordinary fast-forward push
    test_commits $testCount
    git push
  ;;

  forcepush)
    # Force push
    git reset --hard HEAD~$testCount
    test_commits $testCount
    git push -f
  ;;

  commit)
    # Just do a commit in current branch
    test_commits $testCount
  ;;

  forcemultiple)
    # Commit on multiple branches and push all
    git checkout master
    git reset --hard HEAD~$testCount
    test_commits $testCount
    git checkout -b $testBranch
    ( git push -u $remote $testBranch ) > /dev/null 2>&1
    git reset --hard HEAD~$testCount
    test_commits $testCount
    git checkout master
    git push $remote -f --all
  ;;

  multiple)
    # Commit on multiple branches and push all
    git checkout master
    test_commits $testCount
    git checkout -b $testBranch
    ( git push -u $remote $testBranch ) > /dev/null 2>&1
    test_commits $testCount
    git checkout master
    git push $remote --all
  ;;

  merge)
    # Simulate a merge without conflicts
    ( test_commits $testCount
      git push
      git reset --hard HEAD~$testCount
      test_commits $testCount
      git pull -s recursive -X theirs --no-edit ) > /dev/null 2>&1
    git push
  ;;

  tags)
    # Test creation of new tags
    test_tags $testCount 0
    git push --tags
  ;;

  annotatedtags)
    # Test creation of new annotated tags
    test_tags $testCount 1
    git push --tags
  ;;

  deletetags)
    # Tags deletion
    for i in `seq 1 $testCount`; do
      git push $remote :refs/tags/autoTag-$i
      git tag -d autoTag-$i
    done
  ;;

  branch)
    # Test creation of a branch
    ( git branch -D $testBranch
      git push $remote :$testBranch ) > /dev/null 2>&1
    git branch $testBranch
    git push $remote $testBranch:$testBranch
  ;;

  deletebranch)
    # Test creation of a branch
    git branch -D $testBranch
    git push $remote :$testBranch
  ;;

  reset)
    git tag | xargs -L1 -I{} git push $remote :refs/tags/{}
    git tag | xargs -L1 -I{} git tag -d {}
    git push $remote :$testBranch
    git checkout master
    git branch -D $testBranch
    git reset --hard origin/master
    git push -f $remote master:master
  ;;

esac
