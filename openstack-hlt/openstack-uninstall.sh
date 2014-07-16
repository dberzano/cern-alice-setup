#!/bin/bash

cd $(dirname "$0")

function _e() {
  echo -e "\033[34m$1\033[m" >&2
}

function _d() {
  date +%Y%m%d-%H%M%S
}

function _x() {
  echo -e "\033[36m[$(_d)] executing: \033[35m$@\033[36m\033[m" >&2
  "$@"
  r=$?
  if [ $r == 0 ] ; then
    echo -e "\033[32m[$(_d)] finished OK\033[m" >&2
  else
    echo -e "\033[31m[$(_d)] finished with errors: $r, aborting\033[m" >&2
    exit $r
  fi
}

source openstack-install.conf
if [ $? != 0 ] ; then
  _e "cannot find variables!"
  exit 1
fi

# are we in a screen?
_e "check screen"
_x [ "$STY" != '' ]

# remove databases
_x mysql -u root --password=$os_pwd_mysql_root --table -vvv <<EOF
DROP DATABASE IF EXISTS keystone ;
DROP DATABASE IF EXISTS glance ;
DROP DATABASE IF EXISTS nova ;
DROP DATABASE IF EXISTS neutron ;
SHOW DATABASES ;
EOF

# remove all packages
_x yum remove -y \
  iptables-services yum-plugin-priorities openstack-neutron-ml2 openstack-utils \
  openstack-neutron-openvswitch mariadb-server MySQL-python qpid-cpp-server \
  openstack-keystone python-keystoneclient openstack-glance \
  python-glanceclient openstack-nova-api openstack-nova-cert \
  openstack-nova-conductor openstack-nova-console openstack-nova-novncproxy \
  openstack-nova-scheduler python-novaclient openstack-neutron \
  python-neutronclient openstack-nova-compute
