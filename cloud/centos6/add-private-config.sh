#!/bin/bash

#
# apply-private-config.sh -- by Dario Berzano <dario.berzano@cern.ch>
#
# Merges content of the private configuration with a context, output the user-data on stdout.
#
# Usage:
#   apply-private-config.sh <cloud_config_file>
#

cur_dir="$( dirname "$0" )"
cur_dir="$( cd "$cur_dir" ; pwd )"
priv_conf="${cur_dir}/private-config.txt"
cloud_conf="$1"

function pecho() (
  echo -e "\033[35m$1\033[m" >&2
)

if [[ "$cloud_conf" == '' ]] ; then
  pecho "Please specify a cloud-config file."
  exit 1
fi

if [[ ! -f "$priv_conf" ]] ; then
  pecho "Private configuration not found at ${priv_conf}, exiting."
  exit 2
fi

if [[ ! -f "$cloud_conf" ]] ; then
  pecho "Cannot find cloud-config file ${cloud_conf}, exiting."
  exit 3
fi

# Load configuration
sed_command=''

while read line ; do

  # Skip empty lines or #comments
  [[ $line =~ ^\s*(#.*|\s*)$ ]] && continue

  key=${line%%=*}
  val=${line#*=}

  if [[ "$key" == "$line" ]] ; then
    pecho "Invalid line: ${line}, skipped!"
    continue
  fi

  sed_command="${sed_command} ; s|<$key>|$val|g"

done < <( cat "$priv_conf" )

# Applying sed, finally
out_file=$(mktemp /tmp/add-private-config-XXXXX)
cat "$cloud_conf" | sed -e "$sed_command" > "$out_file"
cat "$out_file"
r=$?

if [[ $r != 0 ]] ; then
  pecho "There were errors, please check output!"
  rm -f "$out_file"
  exit $r
fi

# Check if there are potentially unresolved variables
while read unres ; do
  pecho "Warning: potentially unresolved variable at line ${unres}"
done < <( cat "$out_file" | grep -nE '<[A-Za-z0-9_]*>' )
rm -f "$out_file"

exit 0
