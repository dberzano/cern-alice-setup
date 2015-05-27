#!/bin/bash
# Note: use only NoCloud as data source
rm -fr /var/lib/cloud/instance/*
mkdir -p /var/lib/cloud/seed/nocloud-net || exit 1
cp -v /home/cloud-user/cloud-init.txt /var/lib/cloud/seed/nocloud-net/user-data || exit 1
echo '' > /var/lib/cloud/seed/nocloud-net/meta-data
service cloud-init-local restart
service cloud-init restart
service cloud-config restart
service cloud-final restart
