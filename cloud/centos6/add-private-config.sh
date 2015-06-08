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

# Include other files
out_with_includes=$(mktemp /tmp/add-private-config-XXXXX)
OldIFS="$IFS"
IFS='\n'
while read line ; do
  if [[ "$line" =~ ^([[:space:]]*)\<(INCLUDE|INCLUDE_REDUCE):([^>]*)\> ]] ; then
    spaces="${BASH_REMATCH[1]}"
    include="${BASH_REMATCH[3]}"
    if [[ -e "$include" ]] ; then
      exec 3<"$include"
      if [[ "${BASH_REMATCH[2]}" == 'INCLUDE_REDUCE' ]] ; then
        while read  -u 3 inc_line ; do
          echo "${spaces}${inc_line}"
        done | sed -e '/^[[:space:]]*$/d ; /^[[:space:]]*#.*$/d'
      else
        while read  -u 3 inc_line ; do
          echo "${spaces}${inc_line}"
        done
      fi
      exec 3<&-
    else
      pecho "Error: cannot open included file: ${include}"
      rm -f "$out_with_includes"
      exit 1
    fi
  else
    echo "$line"
  fi
done < <( cat "$cloud_conf" ) > "$out_with_includes"
IFS="$OldIFS"

# Applying sed, finally
out_file=$(mktemp /tmp/add-private-config-XXXXX)
cat "$out_with_includes" | sed -e "$sed_command" > "$out_file"
r=$?
rm -f "$out_with_includes"
cat "$out_file"

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
