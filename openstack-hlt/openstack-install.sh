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

function _omnom() {
  to_install=''
  extra_opts=()
  for p in "$@" ; do
    if [ ${p:0:1} == '-' ] ; then
      extra_opts="${extra_opts[@]} ${p}"
    else
      if [ "${p##*.}" == 'rpm' ] ; then
        p=${p##*/}
        p=${p%-*}
      fi
      _e "checking if package is installed: $p"
      rpm -q "$p" > /dev/null 2>&1 || to_install="$to_install $p"
    fi
  done
  if [ "$to_install" != '' ] ; then
    _e "to install: $to_install"
    yum -y ${extra_opts[@]} install $to_install
    return $?
  else
    _e "nothing to install"
    return 0
  fi
}

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
  #_nx "$@";return $?
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

function _i_common() {

  _e "*** common part ***"

  if systemctl is-active NetworkManager.service > /dev/null 2>&1 ; then
    _x systemctl disable NetworkManager.service
    _x systemctl stop NetworkManager.service
    _x systemctl restart network.service
    _x systemctl enable network.service
  fi

  _x yum remove -y firewalld

  _x _omnom http://repos.fedorapeople.org/repos/openstack/openstack-icehouse/rdo-release-icehouse-3.noarch.rpm
  _x _omnom ftp://fr2.rpmfind.net/linux/fedora/linux/development/rawhide/x86_64/os/Packages/p/python-oslo-config-1.2.1-2.fc21.noarch.rpm

  repo=/etc/yum.repos.d/rdo-release.repo
  _x sed -e 's#$releasever#20# ; s#^\s*priority\s*=\s*.*$#priority=1#' -i "$repo"

  _x _omnom iptables-services yum-plugin-priorities openstack-neutron-ml2 openstack-utils openstack-neutron-openvswitch

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

  _e "checking for phys iface ($os_physif), ovs bridge ($os_ovsbr) and integration bridge (br-int)"
  _x [ "$os_physif" != '' ]
  _x [ "$os_ovsbr" != '' ]

  ## network part ###

  if [ "$(ovs-vsctl iface-to-br "$os_physif" 2> /dev/null)" != "$os_ovsbr" ] || ! ovs-vsctl br-exists br-int ; then

    _e "creating bridge $os_ovsbr with port $os_physif"

    # create the bridge
    pref=/etc/sysconfig/network-scripts
    _x rm -f $pref/ifcfg-ovsbr100

    cat > "${pref}/ifcfg-${os_ovsbr}" <<EOF
DEVICE=$os_ovsbr
ONBOOT=yes
BOOTPROTO=dhcp
OVSBOOTPROTO=dhcp
OVSDHCPINTERFACES=$os_physif
DEVICETYPE=ovs
TYPE=OVSBridge
DELAY=0
HOTPLUG=no
EOF
    _x grep -q '^TYPE=OVSBridge$' "${pref}/ifcfg-${os_ovsbr}"

    # create the integration bridge
    cat > "${pref}/ifcfg-br-int" <<EOF
DEVICE=br-int
ONBOOT=yes
BOOTPROTO=none
DEVICETYPE=ovs
TYPE=OVSBridge
DELAY=0
HOTPLUG=no
EOF

    # make a backup
    mkdir -p "${pref}/openstack-backup"
    [ ! -e "${pref}/openstack-backup/ifcfg-$os_physif" ] && _x cp "$pref/ifcfg-$os_physif" "${pref}/openstack-backup/ifcfg-$os_physif"

    (
      grep -E '^\s*UUID=|^\s*HWADDR=|^\s*NAME=' "${pref}/openstack-backup/ifcfg-$os_physif" ;
      cat <<EOF
DEVICETYPE=ovs
TYPE=OVSPort
OVS_BRIDGE=$os_ovsbr
DEVICE=$os_physif
ONBOOT=yes
BOOTPROTO=none
USERCTL=no
PEERDNS=yes
DEFROUTE=no
PEERROUTES=yes
IPV4_FAILURE_FATAL=no
EOF
    ) > "${pref}/ifcfg-${os_physif}"
    _x grep -q '^TYPE=OVSPort$' "${pref}/ifcfg-${os_physif}"

    # restart networking... this can break lots of things
    _e "about to restart network: this can fail!"
    _x systemctl restart network.service
  else
    _e "bridge $os_ovsbr already configured"
  fi

  ## /network part ##

  # neutron: common parts
  cf=/etc/neutron/neutron.conf

  # controller+network+compute
  _x openstack-config --set $cf database connection mysql://neutron:$os_pwd_mysql_neutron@$os_server_fqdn/neutron
  _x openstack-config --set $cf DEFAULT verbose True
  _x openstack-config --set $cf DEFAULT debug True

  # controller+network+compute
  _x openstack-config --set $cf DEFAULT auth_strategy keystone
  _x openstack-config --set $cf keystone_authtoken auth_uri http://$os_server_fqdn:5000
  _x openstack-config --set $cf keystone_authtoken auth_host $os_server_fqdn
  _x openstack-config --set $cf keystone_authtoken auth_protocol http
  _x openstack-config --set $cf keystone_authtoken auth_port 35357
  _x openstack-config --set $cf keystone_authtoken admin_tenant_name service
  _x openstack-config --set $cf keystone_authtoken admin_user neutron
  _x openstack-config --set $cf keystone_authtoken admin_password $os_pwd_ospwd_neutron

  # controller+network+compute
  _x openstack-config --set $cf DEFAULT rpc_backend neutron.openstack.common.rpc.impl_qpid
  _x openstack-config --set $cf DEFAULT qpid_hostname $os_server_fqdn

  # controller+network+compute
  _x openstack-config --set $cf DEFAULT core_plugin ml2
  _x openstack-config --set $cf DEFAULT service_plugins router

  # neutron:ml2: controller+network+compute
  cf=/etc/neutron/plugins/ml2/ml2_conf.ini
  _x openstack-config --set $cf ml2 type_drivers local,flat
  _x openstack-config --set $cf ml2 mechanism_drivers openvswitch,l2population
  _x openstack-config --set $cf ml2_type_flat flat_networks '*'

  for cf in /etc/neutron/plugins/ml2/ml2_conf.ini /etc/neutron/plugins/openvswitch/ovs_neutron_plugin.ini ; do
    _x openstack-config --set $cf DEFAULT verbose True
    _x openstack-config --set $cf DEFAULT debug False

    _x openstack-config --set $cf securitygroup enable_security_group True
    _x openstack-config --set $cf securitygroup firewall_driver neutron.agent.linux.iptables_firewall.OVSHybridIptablesFirewallDriver

    _x openstack-config --set $cf ovs enable_tunneling False
    _x openstack-config --set $cf ovs local_ip $os_current_ip
    _x openstack-config --set $cf ovs network_vlan_ranges physnet1   # mystery
    _x openstack-config --set $cf ovs bridge_mappings physnet1:$os_ovsbr  # mystery
  done

  # !!! http://docs.openstack.org/icehouse/install-guide/install/yum/content/neutron-ml2-network-node.html !!!
  # documentation SUCKS --> on the NETWORK NODE section there are instructions
  # for the COMPUTE NODE networking that go in NOVA.CONF
  cf=/etc/nova/nova.conf
  _x openstack-config --set $cf DEFAULT service_neutron_metadata_proxy true
  _x openstack-config --set $cf DEFAULT neutron_metadata_proxy_shared_secret $os_pwd_mdsecret

  _x ln -nfs plugins/ml2/ml2_conf.ini /etc/neutron/plugin.ini


  # fix packaging bug in fedora
  # init=/etc/systemd/system/multi-user.target.wants/neutron-openvswitch-agent.service # NO, bug in a bug --> https://bugs.launchpad.net/ubuntu/+source/sed/+bug/367211
  init=/usr/lib/systemd/system/neutron-openvswitch-agent.service
  _x sed -e 's#plugins/openvswitch/ovs_neutron_plugin.ini#plugin.ini#g' -i "$init"

  # neutron services
  _x systemctl restart neutron-openvswitch-agent
  _x systemctl enable neutron-openvswitch-agent

}

function _i_head() {
  _e "*** head node part ***"

  _x _omnom mariadb-server MySQL-python qpid-cpp-server \
    openstack-keystone python-keystoneclient \
    openstack-glance python-glanceclient \
    openstack-nova-api openstack-nova-cert openstack-nova-conductor \
    openstack-nova-console openstack-nova-novncproxy openstack-nova-scheduler \
    python-novaclient \
    openstack-neutron python-neutronclient

  my=/etc/my.cnf
  [ ! -e "$my".before_openstack ] && _x cp "$my" "$my".before_openstack
  cat "$my".before_openstack | grep -v 'bind-address|default-storage-engine|innodb_file_per_table|collation-server|init-connect|character-set-server' > "$my"
  _x sed -e "s#\[mysqld\]#[mysqld]\nbind-address = $os_server_ip\ndefault-storage-engine = innodb\ninnodb_file_per_table\ncollation_server = utf8_general_ci\ninit-connect = 'SET NAMES utf8'\ncharacter-set-server = utf8#" -i "$my"

  _e "about to configure mysql for the first time"
  _e "conf is interactive: answer yes to all questions"
  _e "use as root password: $os_pwd_mysql_root"
  _e "the first time, root password is empty, set it to: $os_pwd_mysql_root"
  _e ">> will be run automatically in 10 seconds <<"
  _e ">> 's' to skip, any other key to proceed <<"
  read -t 10 -n 1 ans
  _e ''
  [ "$ans" != 's' ] && [ "$ans" != 'S' ] && _x mysql_secure_installation

  _x systemctl restart mysqld.service
  _x systemctl enable mysqld.service

  qpid=/etc/qpidd.conf
  [ ! -e "$qpid".before_openstack ] && _x cp "$qpid" "$qpid".before_openstack
  cat "$qpid".before_openstack | grep -vE '^\s*auth\s*=' > "$qpid"
  echo -e "\nauth=no" >> "$qpid"
  _x grep -q 'auth=no' "$qpid"

  _x systemctl restart qpidd.service
  _x systemctl enable qpidd.service

  # destroy database, logfiles, configuration
  _e ">> press 'x' in 2 seconds if you want to destroy current configuration <<"
  read -t 2 -n 1 ans
  _e ''
  if [ "$ans" == 'x' ] || [ "$ans" == 'X' ] ; then
    _e 'exterminating...'
    _x mysql -u root --password=$os_pwd_mysql_root --table -vvv <<EOF
DROP DATABASE IF EXISTS keystone ;
DROP DATABASE IF EXISTS glance ;
DROP DATABASE IF EXISTS nova ;
DROP DATABASE IF EXISTS neutron ;
EOF
    _x rm -rf /var/lib/glance/images/*
  fi

  # database creation part!

  _x mysql -u root --password=$os_pwd_mysql_root --table -vvv <<EOF

CREATE DATABASE IF NOT EXISTS keystone ;
GRANT ALL PRIVILEGES ON keystone.* TO 'keystone'@'localhost' IDENTIFIED BY '$os_pwd_mysql_keystone' ;
GRANT ALL PRIVILEGES ON keystone.* TO 'keystone'@'%' IDENTIFIED BY '$os_pwd_mysql_keystone' ;

CREATE DATABASE IF NOT EXISTS glance ;
GRANT ALL PRIVILEGES ON glance.* TO 'glance'@'localhost' IDENTIFIED BY '$os_pwd_mysql_glance' ;
GRANT ALL PRIVILEGES ON glance.* TO 'glance'@'%' IDENTIFIED BY '$os_pwd_mysql_glance' ;

CREATE DATABASE IF NOT EXISTS nova ;
GRANT ALL PRIVILEGES ON nova.* TO 'nova'@'localhost' IDENTIFIED BY '$os_pwd_mysql_nova' ;
GRANT ALL PRIVILEGES ON nova.* TO 'nova'@'%' IDENTIFIED BY '$os_pwd_mysql_nova' ;

CREATE DATABASE IF NOT EXISTS neutron ;
GRANT ALL PRIVILEGES ON neutron.* TO 'neutron'@'localhost' IDENTIFIED BY '$os_pwd_mysql_neutron' ;
GRANT ALL PRIVILEGES ON neutron.* TO 'neutron'@'%' IDENTIFIED BY '$os_pwd_mysql_neutron' ;

SHOW DATABASES ;
SELECT user,host,password FROM mysql.user ;

EOF

  # service: keystone
  cf=/etc/keystone/keystone.conf
  _x openstack-config --set "$cf" DEFAULT admin_token $os_pwd_admin_token
  _x openstack-config --set "$cf" database connection mysql://keystone:$os_pwd_mysql_keystone@$os_server_fqdn/keystone

  if [ ! -d /etc/keystone/ssl ] ; then
    _x keystone-manage pki_setup --keystone-user keystone --keystone-group keystone
    _x chown -R keystone:keystone /etc/keystone/ssl
    _x chmod -R o-rwx /etc/keystone/ssl
  fi

  _x chgrp keystone /var/log/keystone/keystone.log
  _x chmod 0660 /var/log/keystone/keystone.log
  _x sudo -u keystone keystone-manage db_sync

  (crontab -l -u keystone 2>&1 | grep -q token_flush) || \
    echo '@hourly /usr/bin/keystone-manage token_flush >/var/log/keystone/keystone-tokenflush.log 2>&1' >> /var/spool/cron/keystone
  _x grep -q 'keystone-manage token_flush' /var/spool/cron/keystone

  _x systemctl restart openstack-keystone
  _x systemctl enable openstack-keystone

  (
    _e "entering openstack service environment"

    export OS_SERVICE_TOKEN=$os_pwd_admin_token
    export OS_SERVICE_ENDPOINT=http://$os_server_fqdn:35357/v2.0

    # create the admin role
    sudo -Eu nobody keystone role-list | grep -qE '\|\s+admin\s+\|' || \
      _x sudo -Eu nobody keystone role-create --name=admin

    # create the admin tenant
    sudo -Eu nobody keystone tenant-list | grep -qE '\|\s+admin\s+\|' || \
      _x sudo -Eu nobody keystone tenant-create --name=admin --description="Admin Tenant"

    # admin user, and roles
    if ! sudo -Eu nobody keystone user-list | grep -qE '\|\s+admin\s+\|' ; then
      _x sudo -Eu nobody keystone user-create --name=admin --pass=$os_pwd_ospwd_admin --email=admin@dummy.openstack.org
      _x sudo -Eu nobody keystone user-role-add --user=admin --tenant=admin --role=admin
      _x sudo -Eu nobody keystone user-role-add --user=admin --tenant=admin --role=_member_
    fi

    # demo tenant
    sudo -Eu nobody keystone tenant-list | grep -qE '\|\s+demo\s+\|' || \
      _x sudo -Eu nobody keystone tenant-create --name=demo --description="Demo Tenant"

    # demo user, and role
    if ! sudo -Eu nobody keystone user-list | grep -qE '\|\s+demo\s+\|' ; then
      _x sudo -Eu nobody keystone user-create --name=demo --pass=$os_pwd_ospwd_demo --email=demo@dummy.openstack.org
      _x sudo -Eu nobody keystone user-role-add --user=demo --tenant=demo --role=_member_
    fi

    # service tenant
    sudo -Eu nobody keystone tenant-list | grep -qE '\|\s+service\s+\|' || \
      _x sudo -Eu nobody keystone tenant-create --name=service --description="Service Tenant"

    # register keystone service
    sudo -Eu nobody keystone service-list | grep -qE '\|\s+keystone\s+\|' || \
      _x sudo -Eu nobody keystone service-create --name=keystone --type=identity --description="OpenStack Identity"

    # register keystone endpoints
    sudo -Eu nobody keystone endpoint-list | grep -qE '\|'"\s+http://$os_server_fqdn:5000/v2.0\s+"'\|' || \
      _x sudo -Eu nobody keystone endpoint-create \
        --service-id=$(keystone service-list | awk '/ identity / {print $2}') \
        --publicurl=http://$os_server_fqdn:5000/v2.0 \
        --internalurl=http://$os_server_fqdn:5000/v2.0 \
        --adminurl=http://$os_server_fqdn:35357/v2.0

    _e "exiting openstack service environment"
  ) || exit $?

  # try to get a token for test
  #_x keystone --os-username=admin --os-password=$os_pwd_ospwd_admin --os-auth-url=http://$os_server_fqdn:35357/v2.0 token-get

  _e "to use openstack as admin:"
  _e "  export OS_AUTH_URL=http://$os_server_fqdn:35357/v2.0"
  _e "  export OS_USERNAME=admin"
  _e "  export OS_PASSWORD=$os_pwd_ospwd_admin"
  _e "  export OS_TENANT_NAME=admin"

  # service: glance
  _x openstack-config --set /etc/glance/glance-api.conf database connection mysql://glance:$os_pwd_mysql_glance@$os_server_fqdn/glance
  _x openstack-config --set /etc/glance/glance-registry.conf database connection mysql://glance:$os_pwd_mysql_glance@$os_server_fqdn/glance
  _x sudo -u glance glance-manage db_sync

  cf=/etc/glance/glance-api.conf
  _x openstack-config --set $cf keystone_authtoken auth_uri http://$os_server_fqdn:5000
  _x openstack-config --set $cf keystone_authtoken auth_host $os_server_fqdn
  _x openstack-config --set $cf keystone_authtoken auth_port 35357
  _x openstack-config --set $cf keystone_authtoken auth_protocol http
  _x openstack-config --set $cf keystone_authtoken admin_tenant_name service
  _x openstack-config --set $cf keystone_authtoken admin_user glance
  _x openstack-config --set $cf keystone_authtoken admin_password $os_pwd_ospwd_glance
  _x openstack-config --set $cf paste_deploy flavor keystone

  cf=/etc/glance/glance-registry.conf
  _x openstack-config --set $cf keystone_authtoken auth_uri http://$os_server_fqdn:5000
  _x openstack-config --set $cf keystone_authtoken auth_host $os_server_fqdn
  _x openstack-config --set $cf keystone_authtoken auth_port 35357
  _x openstack-config --set $cf keystone_authtoken auth_protocol http
  _x openstack-config --set $cf keystone_authtoken admin_tenant_name service
  _x openstack-config --set $cf keystone_authtoken admin_user glance
  _x openstack-config --set $cf keystone_authtoken admin_password $os_pwd_ospwd_glance
  _x openstack-config --set $cf paste_deploy flavor keystone

  # service: nova controller
  cf=/etc/nova/nova.conf
  _x openstack-config --set $cf database connection mysql://nova:$os_pwd_mysql_nova@$os_server_fqdn/nova
  _x openstack-config --set $cf DEFAULT rpc_backend qpid
  _x openstack-config --set $cf DEFAULT qpid_hostname $os_server_fqdn
  _x openstack-config --set $cf DEFAULT my_ip $os_server_ip
  _x openstack-config --set $cf DEFAULT vncserver_listen $os_server_ip
  _x openstack-config --set $cf DEFAULT vncserver_proxyclient_address $os_server_ip
  _x openstack-config --set $cf DEFAULT auth_strategy keystone
  _x openstack-config --set $cf keystone_authtoken auth_uri http://$os_server_fqdn:5000
  _x openstack-config --set $cf keystone_authtoken auth_host $os_server_fqdn
  _x openstack-config --set $cf keystone_authtoken auth_protocol http
  _x openstack-config --set $cf keystone_authtoken auth_port 35357
  _x openstack-config --set $cf keystone_authtoken admin_user nova
  _x openstack-config --set $cf keystone_authtoken admin_tenant_name service
  _x openstack-config --set $cf keystone_authtoken admin_password $os_pwd_ospwd_nova
  _x openstack-config --set $cf DEFAULT verbose True
  _x sudo -u nova nova-manage db sync

  (
    # unpriv operations: run as nobody, use admin openstack environment
    _e "entering openstack admin environment"

    export OS_AUTH_URL="http://$os_server_fqdn:35357/v2.0"
    export OS_USERNAME=admin
    export OS_PASSWORD=$os_pwd_ospwd_admin
    export OS_TENANT_NAME=admin

    # glance user
    if ! sudo -Eu nobody keystone user-list | grep -qE '\|\s+glance\s+\|' ; then
      _x sudo -Eu nobody keystone user-create --name=glance --pass=$os_pwd_ospwd_glance --email=glance@dummy.openstack.org
      _x sudo -Eu nobody keystone user-role-add --user=glance --tenant=service --role=admin
    fi

    # glance service
    sudo -Eu nobody keystone service-list | grep -qE '\|\s+glance\s+\|' || \
      _x sudo -Eu nobody keystone service-create --name=glance --type=image --description="OpenStack Image Service"

    # glance endpoint
    sudo -Eu nobody keystone endpoint-list | grep -qE '\|'"\s+http://$os_server_fqdn:9292\s+"'\|' || \
      _x sudo -Eu nobody keystone endpoint-create \
        --service-id=$(keystone service-list | awk '/ image / {print $2}') \
        --publicurl=http://$os_server_fqdn:9292 \
        --internalurl=http://$os_server_fqdn:9292 \
        --adminurl=http://$os_server_fqdn:9292

    # nova user
    if ! sudo -Eu nobody keystone user-list | grep -qE '\|\s+nova\s+\|' ; then
      _x sudo -Eu nobody keystone user-create --name=nova --pass=$os_pwd_ospwd_nova --email=nova@dummy.openstack.org
      _x sudo -Eu nobody keystone user-role-add --user=nova --tenant=service --role=admin
    fi

    # nova service
    sudo -Eu nobody keystone service-list | grep -qE '\|\s+nova\s+\|' || \
      _x sudo -Eu nobody keystone service-create --name=nova --type=compute --description="OpenStack Compute"

    # nova endpoint
    sudo -Eu nobody keystone endpoint-list | grep -qE '\|'"\s+http://$os_server_fqdn:8774/v2/%\(tenant_id\)s\s+"'\|' || \
      _x sudo -Eu nobody keystone endpoint-create \
        --service-id=$(keystone service-list | awk '/ compute / {print $2}') \
        --publicurl=http://$os_server_fqdn:8774/v2/%\(tenant_id\)s \
        --internalurl=http://$os_server_fqdn:8774/v2/%\(tenant_id\)s \
        --adminurl=http://$os_server_fqdn:8774/v2/%\(tenant_id\)s

    # neutron user
    if ! sudo -Eu nobody keystone user-list | grep -qE '\|\s+neutron\s+\|' ; then
      _x sudo -Eu nobody keystone user-create --name neutron --pass=$os_pwd_ospwd_neutron --email neutron@dummy.openstack.org
      _x sudo -Eu nobody keystone user-role-add --user neutron --tenant service --role admin
    fi

    # neutron service
    sudo -Eu nobody keystone service-list | grep -qE '\|\s+neutron\s+\|' || \
      _x sudo -Eu nobody keystone service-create --name neutron --type network --description "OpenStack Networking"

    # neutron endpoint
    sudo -Eu nobody keystone endpoint-list | grep -qE '\|'"\s+http://$os_server_fqdn:9696\s+"'\|' || \
      _x sudo -Eu nobody keystone endpoint-create \
        --service-id $(keystone service-list | awk '/ network / {print $2}') \
        --publicurl http://$os_server_fqdn:9696 \
        --adminurl http://$os_server_fqdn:9696 \
        --internalurl http://$os_server_fqdn:9696

    _e "list of services"
    _x sudo -Eu nobody keystone service-list

    _e "exiting openstack admin environment"
  ) || exit $?

  ## neutron ##

  # neutron
  cf=/etc/neutron/neutron.conf

  # controller
  _x openstack-config --set $cf DEFAULT notify_nova_on_port_status_changes True
  _x openstack-config --set $cf DEFAULT notify_nova_on_port_data_changes True
  _x openstack-config --set $cf DEFAULT nova_url http://$os_server_fqdn:8774/v2
  _x openstack-config --set $cf DEFAULT nova_admin_username nova
  _x openstack-config --set $cf DEFAULT nova_admin_tenant_id $(export OS_SERVICE_TOKEN=$os_pwd_admin_token ; export OS_SERVICE_ENDPOINT=http://$os_server_fqdn:35357/v2.0 ; keystone tenant-list | awk '/ service / { print $2 }')
  _x openstack-config --set $cf DEFAULT nova_admin_password $os_pwd_ospwd_nova
  _x openstack-config --set $cf DEFAULT nova_admin_auth_url http://$os_server_fqdn:35357/v2.0

  # controller (tell nova to use neutron)
  cf=/etc/nova/nova.conf
  _x openstack-config --set $cf DEFAULT network_api_class nova.network.neutronv2.api.API
  _x openstack-config --set $cf DEFAULT neutron_url http://$os_server_fqdn:9696
  _x openstack-config --set $cf DEFAULT neutron_auth_strategy keystone
  _x openstack-config --set $cf DEFAULT neutron_admin_tenant_name service
  _x openstack-config --set $cf DEFAULT neutron_admin_username neutron
  _x openstack-config --set $cf DEFAULT neutron_admin_password $os_pwd_ospwd_neutron
  _x openstack-config --set $cf DEFAULT neutron_admin_auth_url http://$os_server_fqdn:35357/v2.0
  _x openstack-config --set $cf DEFAULT linuxnet_interface_driver nova.network.linux_net.LinuxOVSInterfaceDriver
  _x openstack-config --set $cf DEFAULT firewall_driver nova.virt.firewall.NoopFirewallDriver
  _x openstack-config --set $cf DEFAULT security_group_api neutron

  # network (metadata agent)
  cf=/etc/neutron/metadata_agent.ini
  _x openstack-config --set $cf DEFAULT auth_url http://$os_server_fqdn:5000/v2.0
  _x openstack-config --set $cf DEFAULT auth_region regionOne
  _x openstack-config --set $cf DEFAULT admin_tenant_name service
  _x openstack-config --set $cf DEFAULT admin_user neutron
  _x openstack-config --set $cf DEFAULT admin_password $os_pwd_ospwd_neutron
  _x openstack-config --set $cf DEFAULT nova_metadata_ip $os_server_fqdn
  _x openstack-config --set $cf DEFAULT metadata_proxy_shared_secret $os_pwd_mdsecret

  # network (dhcp agent)
  cf=/etc/neutron/dhcp_agent.ini
  _x openstack-config --set $cf DEFAULT interface_driver neutron.agent.linux.interface.OVSInterfaceDriver
  _x openstack-config --set $cf DEFAULT dhcp_driver neutron.agent.linux.dhcp.Dnsmasq
  _x openstack-config --set $cf DEFAULT use_namespaces True
  _x openstack-config --set $cf DEFAULT verbose True

  # network (l3)
  cf=/etc/neutron/l3_agent.ini
  _x openstack-config --set $cf DEFAULT interface_driver neutron.agent.linux.interface.OVSInterfaceDriver
  _x openstack-config --set $cf DEFAULT use_namespaces True

  # cat $cf | sed -e '/^$/d' | grep -v '^\s*#' | sed -e 's#^\[#\n[#'

  ## /neutron ##

  # start services at the end of everything

  # glance
  _x systemctl restart openstack-glance-api
  _x systemctl restart openstack-glance-registry
  _x systemctl enable openstack-glance-api
  _x systemctl enable openstack-glance-registry

  # neutron
  _x systemctl restart openvswitch
  _x systemctl restart neutron-server
  _x systemctl restart neutron-metadata-agent
  _x systemctl restart neutron-dhcp-agent
  _x systemctl restart neutron-l3-agent
  _x systemctl enable openvswitch
  _x systemctl enable neutron-server
  _x systemctl enable neutron-metadata-agent
  _x systemctl enable neutron-dhcp-agent
  _x systemctl enable neutron-l3-agent

  # nova
  _x systemctl restart openstack-nova-api
  _x systemctl restart openstack-nova-cert
  _x systemctl restart openstack-nova-consoleauth
  _x systemctl restart openstack-nova-scheduler
  _x systemctl restart openstack-nova-conductor
  _x systemctl restart openstack-nova-novncproxy
  _x systemctl enable openstack-nova-api
  _x systemctl enable openstack-nova-cert
  _x systemctl enable openstack-nova-consoleauth
  _x systemctl enable openstack-nova-scheduler
  _x systemctl enable openstack-nova-conductor
  _x systemctl enable openstack-nova-novncproxy

  (
    # register an image
    _e "entering openstack admin environment"

    export OS_AUTH_URL="http://$os_server_fqdn:35357/v2.0"
    export OS_USERNAME=admin
    export OS_PASSWORD=$os_pwd_ospwd_admin
    export OS_TENANT_NAME=admin

    if ! sudo -Eu nobody glance image-list | grep -qE '\|\s+CirrOS Test Image\s+\|' ; then
      t=$(mktemp)
      chown nobody:nobody "$t"
      _x sudo -Eu nobody curl -SsL http://cdn.download.cirros-cloud.net/0.3.2/cirros-0.3.2-x86_64-disk.img -o "$t"
      _x sudo -Eu nobody glance image-create --name='CirrOS Test Image' --disk-format='qcow2' --container-format='bare' --is-public='true' < "$t"
      rm -f "$t"
    fi

    # --> https://access.redhat.com/documentation/en-US/Red_Hat_Enterprise_Linux_OpenStack_Platform/4/html/Getting_Started_Guide/sect-Working_with_OpenStack_Networking.html

    # create a network
    if ! sudo -Eu nobody neutron net-list | grep -qE '\|\s+flat-net\s+\|' ; then
      _x sudo -Eu nobody neutron net-create flat-net \
        --router:external True \
        --provider:network_type flat \
        --provider:physical_network physnet1
    fi

    # create a subnetwork
    if ! sudo -Eu nobody neutron subnet-list | grep -qE '\|\s+flat-subnet\s+\|' ; then
      _x sudo -Eu nobody neutron subnet-create \
        --gateway 10.162.223.254 \
        --allocation-pool start=10.162.208.2,end=10.162.223.253 \
        --disable-dhcp \
        --name flat-subnet \
        flat-net \
        10.162.208.0/20
    fi

    _e "exiting openstack admin environment"
  ) || exit $?

}

function _i_worker() {
  _e "*** worker node part ***"

  _x _omnom openstack-nova-compute --disablerepo='slc6-*'

  # service: nova compute
  cf=/etc/nova/nova.conf
  _x openstack-config --set $cf database connection mysql://nova:$os_pwd_mysql_nova@$os_server_fqdn/nova
  _x openstack-config --set $cf DEFAULT auth_strategy keystone
  _x openstack-config --set $cf keystone_authtoken auth_uri http://$os_server_fqdn:5000
  _x openstack-config --set $cf keystone_authtoken auth_host $os_server_fqdn
  _x openstack-config --set $cf keystone_authtoken auth_protocol http
  _x openstack-config --set $cf keystone_authtoken auth_port 35357
  _x openstack-config --set $cf keystone_authtoken admin_user nova
  _x openstack-config --set $cf keystone_authtoken admin_tenant_name service
  _x openstack-config --set $cf keystone_authtoken admin_password $os_pwd_ospwd_nova
  _x openstack-config --set $cf DEFAULT verbose True

  # nova compute --> qpid
  _x openstack-config --set $cf DEFAULT rpc_backend qpid
  _x openstack-config --set $cf DEFAULT qpid_hostname $os_server_fqdn

  # nova compute --> vnc
  _x openstack-config --set $cf DEFAULT my_ip $os_current_ip
  _x openstack-config --set $cf DEFAULT vnc_enabled True
  _x openstack-config --set $cf DEFAULT vncserver_listen 0.0.0.0
  _x openstack-config --set $cf DEFAULT vncserver_proxyclient_address $os_current_ip
  _x openstack-config --set $cf DEFAULT novncproxy_base_url http://$os_server_fqdn:6080/vnc_auto.html

  # nova compute --> glance
  _x openstack-config --set $cf DEFAULT glance_host $os_server_fqdn

  # nova compute --> qemu (or docker?)
  _x openstack-config --set $cf libvirt virt_type qemu

  # nova compute services
  _x systemctl restart openvswitch
  _x systemctl restart libvirtd
  _x systemctl restart dbus
  _x systemctl restart openstack-nova-compute
  _x systemctl enable openvswitch
  _x systemctl enable libvirtd
  _x systemctl enable dbus
  _x systemctl enable openstack-nova-compute

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
        _i_head
        return $?
      ;;
      --worker)
        _i_common || return $?
        _i_worker
        return $?
      ;;
    esac
    shift
  done

  _e "nothing to do"
  return 1

}

_m "$@" || exit $?
