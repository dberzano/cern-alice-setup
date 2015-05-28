#!/bin/bash

# Echo every command, and make every command fatal
set -x
set -e

# Use NoCloud as data source
cat /etc/cloud/cloud.cfg | \
  sed -e 's|^.*datasource_list:.*$|datasource_list: [ '\''NoCloud'\'' ]|' > \
  /etc/cloud/cloud.cfg.0 && mv /etc/cloud/cloud.cfg.0 /etc/cloud/cloud.cfg

### Custom cleanup ###
true
### /Custom cleanup ###

# Remove data from previous runs
rm -fr /var/lib/cloud/instance/*

# Create the directory where the NoCloud module looks for user-data and meta-data
mkdir -p /var/lib/cloud/seed/nocloud-net || exit 1

# Make our user-data visible to the NoCloud module (copy)
cp -v /home/cloud-user/cloud-init.txt /var/lib/cloud/seed/nocloud-net/user-data || exit 1

# Create an empty meta-data (without meta-data, it will fail)
echo '' > /var/lib/cloud/seed/nocloud-net/meta-data

# Execute the cloud-init contextualization phases in order
service cloud-init-local restart
service cloud-init restart
service cloud-config restart
service cloud-final restart
