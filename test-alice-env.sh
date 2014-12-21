#!/bin/bash

#
# Test environment script
#

env='alice-env.sh'
upd='.alice-env.updated'

# assume envscript is one level up
cd "$( dirname "$0" )"/..

function po() (
  echo -e "\033[35m$1\033[m" >&2
)

function change_script() (
  echo '' >> "$env"
  echo '# dummy line to force update #' >> "$env"
)

function force_update() (
  rm -f "$upd"
)

function source_script() {
  source "$env" "$@"
}

# test #0: just source
po 'sourcing unmodified, quietly'
cp cern-alice-setup/alice-env.sh "$env"
source_script -q -n 1

# # test #1: source by forcing update
# force_update
# change_script
# po 'simulating outdated script and sourcing'
# source_script -q -n 1

# # test #2: explicitly tell to update
# change_script
# po 'update explicitly'
# source_script -q -n 1 -u

# test #3: source by name
po 'enabling feature by name'
source_script -n 0 -m "aliroot=master-linux root=v5-34-22"
