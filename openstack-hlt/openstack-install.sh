#!/bin/bash

#
# openstack-install.sh -- by Dario Berzano <dario.berzano@cern.ch>
#
# Helper for installing OpenStack IceHouse on Fedora 19.
#

cd $( dirname "$0" )

# variables
export LANG=C
os_unpriv=$( stat -c "%U" "$0" )
os_conffile="$PWD/openstack-install.conf"

function _d() {
  date +%Y%m%d-%H%M%S
}

function _e() {
  echo -e "\033[34m$1\033[m" >&2
}

function _nx() {
  echo -e "\033[33m[$(_d)] skipping: \033[35m$@\033[36m\033[m" >&2
}

function _x() {
  echo -e "\033[36m[$(_d)] executing: \033[35m$@\033[36m\033[m" >&2
  # echo -en "\033[36m[$(_d)] executing: \033[35m$@\033[36m? [\033[32my\033[36m/\033[31mn\033[36m, default: \033[31mn\033[36m]\033[m " >&2
  # read -n 1 ans
  # echo ''
  # if [ "${ans:0:1}" != 'y' ] && [ "${ans:0:1}" != 'Y' ] ; then
  #   echo -e "\033[33m[$(_d)] skipping\033[m" >&2
  #   return 0
  # fi
  "$@"
  r=$?
  if [ $r == 0 ] ; then
    echo -e "\033[32m[$(_d)] finished OK\033[m" >&2
  else
    echo -e "\033[31m[$(_d)] finished with errors: $r, aborting\033[m" >&2
    exit $r
  fi
}

function _i_common() {

  _e "*** common part ***"

  _nx systemctl disable NetworkManager.service
  _nx systemctl stop NetworkManager.service
  _nx systemctl restart network.service
  _nx systemctl enable network.service

  _nx yum remove -y firewalld
  _nx yum install -y iptables-services yum-plugin-priorities

  _nx yum remove -y rdo-release-icehouse
  _nx yum install -y http://repos.fedorapeople.org/repos/openstack/openstack-icehouse/rdo-release-icehouse-3.noarch.rpm

  repo=/etc/yum.repos.d/rdo-release.repo
  _nx sed -e 's#$releasever#20# ; s#^\s*priority\s*=\s*.*$#priority=1#' -i "$repo"

  _nx yum remove -y python-oslo-config
  _nx yum install -y ftp://fr2.rpmfind.net/linux/fedora/linux/releases/20/Everything/x86_64/os/Packages/p/python-oslo-config-1.2.0-0.5.a3.fc20.noarch.rpm

  _nx yum install -y openstack-utils

  # generate all the passwords; save them to a configuration file
  source "$os_conffile" 2> /dev/null
  t=$(mktemp)
  cat "$os_conffile" > "$t" 2>/dev/null

  pwd_prefix='os_pwd_'
  pwds=( admin_token mdsecret mysql_glance mysql_keystone mysql_neutron \
         mysql_nova mysql_root ospwd_admin ospwd_demo ospwd_glance \
         ospwd_neutron ospwd_nova )

  for pn in ${pwds[@]} ; do
    # pn: password name
    # pw: password value
    # pv: password variable
    pv=${pwd_prefix}${pn}
    pw=$( eval echo \$${pv} )
    if [ "$pw" == '' ] ; then
      pw=$( openssl rand -hex 10 )
      _e "password $pn = $pw (generated)"
    else
      _e "password $pn = $pw (from config)"
    fi
    cat "$t" | grep -vE "\s*${pv}=" > "$t.0"
    mv "$t.0" "$t"
    echo "${pv}=${pw}" >> "$t"
  done

  mv "$t" "$os_conffile"
  chown $os_unpriv "$os_conffile"
  chmod 0600 "$os_conffile"
  source "$os_conffile"

  _e "checking if server address is set: $os_server_ip ($os_server_fqdn)"
  _x [ "$os_server_ip" != '' ]
  _x [ "$os_server_fqdn" != '' ]

  # custom part! beware!
  raw=$( ifconfig | grep -E '\s*inet 10.162.128.' 2> /dev/null | head -n1 )
  if [[ "$raw" =~ (([0-9]{1,3}\.){3}[0-9]{1,3}) ]] ; then   # fix color ))
    os_current_ip="${BASH_REMATCH[1]}"
  fi
  _e "current ip: $os_current_ip"
  _x [ "$os_current_ip" != '' ]

}

function _i_head() {
  _e "*** head node part ***"

  _nx yum install -y mariadb-server MySQL-python qpid-cpp-server \
    openstack-keystone python-keystoneclient \
    openstack-glance python-glanceclient \
    openstack-nova-api openstack-nova-cert openstack-nova-conductor \
    openstack-nova-console openstack-nova-novncproxy openstack-nova-scheduler \
    python-novaclient

  my=/etc/my.cnf
  [ ! -e "$my".before_openstack ] && _x cp "$my" "$my".before_openstack
  cat "$my".before_openstack | grep -v 'bind-address|default-storage-engine|innodb_file_per_table|collation-server|init-connect|character-set-server' > "$my"
  _nx sed -e "s#\[mysqld\]#[mysqld]\nbind-address = $os_server_ip\ndefault-storage-engine = innodb\ninnodb_file_per_table\ncollation_server = utf8_general_ci\ninit-connect = 'SET NAMES utf8'\ncharacter-set-server = utf8#" -i "$my"

  _nx systemctl restart mysqld.service
  _nx systemctl enable mysqld.service

  _e "about to configure mysql for the first time"
  _e "conf is interactive: answer yes to all questions"
  _e "use as root password: $os_pwd_mysql_root"
  _e "press enter to start..."
  _nx read
  _nx mysql_secure_installation

  qpid=/etc/qpidd.conf
  [ ! -e "$qpid".before_openstack ] && _x cp "$qpid" "$qpid".before_openstack
  cat "$qpid".before_openstack | grep -vE '^\s*auth\s*=' > "$qpid"
  echo -e "\nauth=no" >> "$qpid"
  _nx grep -q 'auth=no' "$qpid"

  _nx systemctl restart qpidd.service
  _nx systemctl enable qpidd.service

  # database creation part!

  _nx mysql -u root --password=$os_pwd_mysql_root --table -vvv <<EOF

CREATE DATABASE IF NOT EXISTS keystone ;
GRANT ALL PRIVILEGES ON keystone.* TO 'keystone'@'localhost' IDENTIFIED BY '$os_pwd_mysql_keystone' ;
GRANT ALL PRIVILEGES ON keystone.* TO 'keystone'@'%' IDENTIFIED BY '$os_pwd_mysql_keystone' ;

CREATE DATABASE IF NOT EXISTS glance ;
GRANT ALL PRIVILEGES ON glance.* TO 'glance'@'localhost' IDENTIFIED BY '$os_pwd_mysql_glance' ;
GRANT ALL PRIVILEGES ON glance.* TO 'glance'@'%' IDENTIFIED BY '$os_pwd_mysql_glance' ;

CREATE DATABASE IF NOT EXISTS nova ;
GRANT ALL PRIVILEGES ON nova.* TO 'nova'@'localhost' IDENTIFIED BY '$os_pwd_mysql_nova';
GRANT ALL PRIVILEGES ON nova.* TO 'nova'@'%' IDENTIFIED BY '$os_pwd_mysql_nova' ;

SHOW DATABASES ;
SELECT user,host,password FROM mysql.user ;

EOF

  # service: keystone
  cf=/etc/keystone/keystone.conf
  _nx openstack-config --set "$cf" DEFAULT admin_token $os_pwd_admin_token
  _nx openstack-config --set "$cf" database connection mysql://keystone:$os_pwd_mysql_keystone@$os_server_fqdn/keystone

  if [ ! -d /etc/keystone/ssl ] ; then
    _x keystone-manage pki_setup --keystone-user keystone --keystone-group keystone
    _x chown -R keystone:keystone /etc/keystone/ssl
    _x chmod -R o-rwx /etc/keystone/ssl
  fi

  _nx chgrp keystone /var/log/keystone/keystone.log
  _nx chmod 0660 /var/log/keystone/keystone.log
  _nx sudo -u keystone keystone-manage db_sync

  (crontab -l -u keystone 2>&1 | grep -q token_flush) || \
    echo '@hourly /usr/bin/keystone-manage token_flush >/var/log/keystone/keystone-tokenflush.log 2>&1' >> /var/spool/cron/keystone
  _nx grep -q 'keystone-manage token_flush' /var/spool/cron/keystone

  _nx systemctl restart openstack-keystone
  _nx systemctl enable openstack-keystone

  (
    export OS_SERVICE_TOKEN=$os_pwd_admin_token
    export OS_SERVICE_ENDPOINT=http://$os_server_fqdn:35357/v2.0

    # admin user, admin tenant and service tenant
    _nx keystone user-create --name=admin --pass=$os_pwd_ospwd_admin --email=admin@dummy.openstack.org

    _nx keystone role-create --name=admin
    _nx keystone tenant-create --name=admin --description="Admin Tenant"
    _nx keystone user-role-add --user=admin --tenant=admin --role=admin
    _nx keystone user-role-add --user=admin --role=_member_ --tenant=admin

    _nx keystone user-create --name=demo --pass=$os_pwd_ospwd_demo --email=demo@dummy.openstack.org
    _nx keystone tenant-create --name=demo --description="Demo Tenant"
    _nx keystone user-role-add --user=demo --role=_member_ --tenant=demo

    _nx keystone tenant-create --name=service --description="Service Tenant"

    # register service endpoints
    _nx keystone service-create --name=keystone --type=identity --description="OpenStack Identity"
    _nx keystone endpoint-create \
      --service-id=$(keystone service-list | awk '/ identity / {print $2}') \
      --publicurl=http://$os_server_fqdn:5000/v2.0 \
      --internalurl=http://$os_server_fqdn:5000/v2.0 \
      --adminurl=http://$os_server_fqdn:35357/v2.0
  ) || exit $?

  # try to get a token for test
  #_x keystone --os-username=admin --os-password=$os_pwd_ospwd_admin --os-auth-url=http://$os_server_fqdn:35357/v2.0 token-get

  _e "to use openstack as admin:"
  _e "  export OS_AUTH_URL=http://$os_server_fqdn:35357/v2.0"
  _e "  export OS_USERNAME=admin"
  _e "  export OS_PASSWORD=$os_pwd_ospwd_admin"
  _e "  export OS_TENANT_NAME=admin"

  # service: glance
  _nx openstack-config --set /etc/glance/glance-api.conf database connection mysql://glance:$os_pwd_mysql_glance@$os_server_fqdn/glance
  _nx openstack-config --set /etc/glance/glance-registry.conf database connection mysql://glance:$os_pwd_mysql_glance@$os_server_fqdn/glance
  _nx sudo -u glance glance-manage db_sync

  cf=/etc/glance/glance-api.conf
  _nx openstack-config --set $cf keystone_authtoken auth_uri http://$os_server_fqdn:5000
  _nx openstack-config --set $cf keystone_authtoken auth_host $os_server_fqdn
  _nx openstack-config --set $cf keystone_authtoken auth_port 35357
  _nx openstack-config --set $cf keystone_authtoken auth_protocol http
  _nx openstack-config --set $cf keystone_authtoken admin_tenant_name service
  _nx openstack-config --set $cf keystone_authtoken admin_user glance
  _nx openstack-config --set $cf keystone_authtoken admin_password $os_pwd_ospwd_glance
  _nx openstack-config --set $cf paste_deploy flavor keystone

  cf=/etc/glance/glance-registry.conf
  _nx openstack-config --set $cf keystone_authtoken auth_uri http://$os_server_fqdn:5000
  _nx openstack-config --set $cf keystone_authtoken auth_host $os_server_fqdn
  _nx openstack-config --set $cf keystone_authtoken auth_port 35357
  _nx openstack-config --set $cf keystone_authtoken auth_protocol http
  _nx openstack-config --set $cf keystone_authtoken admin_tenant_name service
  _nx openstack-config --set $cf keystone_authtoken admin_user glance
  _nx openstack-config --set $cf keystone_authtoken admin_password $os_pwd_ospwd_glance
  _nx openstack-config --set $cf paste_deploy flavor keystone

  # service: nova controller
  cf=/etc/nova/nova.conf
  _nx openstack-config --set $cf database connection mysql://nova:$os_pwd_mysql_nova@$os_server_fqdn/nova
  _nx openstack-config --set $cf DEFAULT rpc_backend qpid
  _nx openstack-config --set $cf DEFAULT qpid_hostname $os_server_fqdn
  _nx openstack-config --set $cf DEFAULT my_ip $os_server_ip
  _nx openstack-config --set $cf DEFAULT vncserver_listen $os_server_ip
  _nx openstack-config --set $cf DEFAULT vncserver_proxyclient_address $os_server_ip
  _nx openstack-config --set $cf DEFAULT auth_strategy keystone
  _nx openstack-config --set $cf keystone_authtoken auth_uri http://$os_server_fqdn:5000
  _nx openstack-config --set $cf keystone_authtoken auth_host $os_server_fqdn
  _nx openstack-config --set $cf keystone_authtoken auth_protocol http
  _nx openstack-config --set $cf keystone_authtoken auth_port 35357
  _nx openstack-config --set $cf keystone_authtoken admin_user nova
  _nx openstack-config --set $cf keystone_authtoken admin_tenant_name service
  _nx openstack-config --set $cf keystone_authtoken admin_password $os_pwd_ospwd_nova
  _nx sudo -u nova nova-manage db sync

  (
    # unpriv operations: run as nobody, use admin openstack environment

    export OS_AUTH_URL="http://$os_server_fqdn:35357/v2.0"
    export OS_USERNAME=admin
    export OS_PASSWORD=$os_pwd_ospwd_admin
    export OS_TENANT_NAME=admin

    # glance
    _nx sudo -Eu nobody keystone user-create --name=glance --pass=$os_pwd_ospwd_glance --email=glance@dummy.openstack.org
    _nx sudo -Eu nobody keystone user-role-add --user=glance --tenant=service --role=admin
    _nx sudo -Eu nobody keystone service-create --name=glance --type=image \
      --description="OpenStack Image Service"
    _nx sudo -Eu nobody keystone endpoint-create \
      --service-id=$(keystone service-list | awk '/ image / {print $2}') \
      --publicurl=http://$os_server_fqdn:9292 \
      --internalurl=http://$os_server_fqdn:9292 \
      --adminurl=http://$os_server_fqdn:9292

    # nova
    _nx sudo -Eu nobody keystone user-create --name=nova --pass=$os_pwd_ospwd_nova --email=nova@dummy.openstack.org
    _nx sudo -Eu nobody keystone user-role-add --user=nova --tenant=service --role=admin
    _nx sudo -Eu nobody keystone service-create --name=nova --type=compute --description="OpenStack Compute"
    _nx sudo -Eu nobody keystone endpoint-create \
      --service-id=$(keystone service-list | awk '/ compute / {print $2}') \
      --publicurl=http://$os_server_fqdn:8774/v2/%\(tenant_id\)s \
      --internalurl=http://$os_server_fqdn:8774/v2/%\(tenant_id\)s \
      --adminurl=http://$os_server_fqdn:8774/v2/%\(tenant_id\)s
  ) || exit $?

  # start services at the end of everything

  # glance
  _nx systemctl restart openstack-glance-api
  _nx systemctl restart openstack-glance-registry
  _nx systemctl enable openstack-glance-api
  _nx systemctl enable openstack-glance-registry

  # nova
  _nx systemctl restart openstack-nova-api
  _nx systemctl restart openstack-nova-cert
  _nx systemctl restart openstack-nova-consoleauth
  _nx systemctl restart openstack-nova-scheduler
  _nx systemctl restart openstack-nova-conductor
  _nx systemctl restart openstack-nova-novncproxy
  _nx systemctl enable openstack-nova-api
  _nx systemctl enable openstack-nova-cert
  _nx systemctl enable openstack-nova-consoleauth
  _nx systemctl enable openstack-nova-scheduler
  _nx systemctl enable openstack-nova-conductor
  _nx systemctl enable openstack-nova-novncproxy

  (
    # register an image
    export OS_AUTH_URL="http://$os_server_fqdn:35357/v2.0"
    export OS_USERNAME=admin
    export OS_PASSWORD=$os_pwd_ospwd_admin
    export OS_TENANT_NAME=admin
    _nx curl -SsL http://cdn.download.cirros-cloud.net/0.3.2/cirros-0.3.2-x86_64-disk.img -o /tmp/cirros.img
    [ -e /tmp/cirros.img ] || touch /tmp/cirros.img
    _nx glance image-create --name='CirrOS Test Image' --disk-format='qcow2' --container-format='bare' --is-public='true' < /tmp/cirros.img
    rm -f /tmp/cirros.img
  ) || exit $?

}

function _i_worker() {
  _e "*** worker node part ***"

  _nx yum install -y openstack-nova-compute --disablerepo='slc6-*'

  # service: nova compute
  cf=/etc/nova/nova.conf
  _nx openstack-config --set $cf database connection mysql://nova:$os_pwd_mysql_nova@$os_server_fqdn/nova
  _nx openstack-config --set $cf DEFAULT auth_strategy keystone
  _nx openstack-config --set $cf keystone_authtoken auth_uri http://$os_server_fqdn:5000
  _nx openstack-config --set $cf keystone_authtoken auth_host $os_server_fqdn
  _nx openstack-config --set $cf keystone_authtoken auth_protocol http
  _nx openstack-config --set $cf keystone_authtoken auth_port 35357
  _nx openstack-config --set $cf keystone_authtoken admin_user nova
  _nx openstack-config --set $cf keystone_authtoken admin_tenant_name service
  _nx openstack-config --set $cf keystone_authtoken admin_password $os_pwd_ospwd_nova

  # nova compute --> qpid
  _nx openstack-config --set $cf DEFAULT rpc_backend qpid
  _nx openstack-config --set $cf DEFAULT qpid_hostname $os_server_fqdn

  # nova compute --> vnc
  _nx openstack-config --set $cf DEFAULT my_ip $os_current_ip
  _nx openstack-config --set $cf DEFAULT vnc_enabled True
  _nx openstack-config --set $cf DEFAULT vncserver_listen 0.0.0.0
  _nx openstack-config --set $cf DEFAULT vncserver_proxyclient_address $os_current_ip
  _nx openstack-config --set $cf DEFAULT novncproxy_base_url http://$os_server_fqdn:6080/vnc_auto.html

  # nova compute --> glance
  _nx openstack-config --set $cf DEFAULT glance_host $os_server_fqdn

  # nova compute --> qemu (or docker?)
  _nx openstack-config --set $cf libvirt virt_type qemu

  # nova compute services
  _nx systemctl restart libvirtd
  _nx systemctl restart dbus
  _nx systemctl restart openstack-nova-compute
  _nx systemctl enable libvirtd
  _nx systemctl enable dbus
  _nx systemctl enable openstack-nova-compute

}

function _m() {

  if [ `whoami` != 'root' ] ; then
    _e "you must be root to install things: exiting"
    return 1
  elif [ "$STY" == '' ] ; then
    _e "you must be inside a screen for safety: exiting"
    return 1
  fi

  _e "unpriv user: $os_unpriv"

  while [ $# -gt 0 ] ; do
    case "$1" in
      --head)
        _i_common || return $?
        _i_head || return $?
      ;;
      --worker)
        _i_common || return $?
        _i_worker || return $?
      ;;
    esac
    shift
  done

}

_m "$@" || exit $?
