#!/bin/bash
netid=$( nova net-list | grep -E '\|\s+(vlan|flat)-net\s+\|' | head -n1 | awk '{ print $2 }' )
if [ "$netid" == '' ] ; then
  echo 'no network'
  exit 1
fi
prefix='demo-inst-'
greatest=0
while read i ; do
  if [[ "$i" =~ ^[^0-9]*([0-9]+)$ ]] ; then
    n=${BASH_REMATCH[1]}
    [ $n -gt $greatest ] && greatest=$n
  fi
done < <( nova list | awk '{ print $4 }' | grep -E "^$prefix[0-9]+$" )
let greatest++
name="$prefix$greatest"
echo -n "launching $name, ok? (y) "
read -n1 ans
echo ''
if [ "$ans" != 'y' ] && [ "$ans" != 'Y' ] ; then
  echo "cancelled"
  exit 1
fi
exec nova boot \
  --flavor m1.tiny \
  --image 'CirrOS Test Image' \
  --nic net-id="$netid" \
  --security-group default \
  $name
