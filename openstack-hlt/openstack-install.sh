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

################################################################################
# UTILITY FUNCTIONS
################################################################################
function _omnom() {
  to_install=''
  extra_opts=()
  for p in "$@" ; do
    pkgfull="$p"
    if [ ${p:0:1} == '-' ] ; then
      extra_opts="${extra_opts[@]} ${p}"
    else
      if [ "${p##*.}" == 'rpm' ] ; then
        p=${p##*/}
        p=${p%-*}
      fi
      _e "checking if package is installed: $p"
      rpm -q "$p" > /dev/null 2>&1 || to_install="$to_install $pkgfull"
    fi
  done
  if [ "$to_install" != '' ] ; then
    _e "to install:$to_install"
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

################################################################################
# COMMON CONFIGURATION
################################################################################
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
  _x _omnom ftp://bo.mirror.garr.it/pub/1/fedora/linux/updates/20/x86_64/python-oslo-config-1.2.1-2.fc20.noarch.rpm

  repo=/etc/yum.repos.d/rdo-release.repo
  _x sed -e 's#$releasever#20# ; s#^\s*priority\s*=\s*.*$#priority=1#' -i "$repo"

  # install common packages
  _x _omnom iptables-services yum-plugin-priorities openstack-utils \
    openstack-nova-api tcpdump mtr htop

  # generate all the passwords; save them to a configuration file
  source "$os_conffile" 2> /dev/null
  t=$(mktemp)
  cat "$os_conffile" > "$t" 2>/dev/null

  pwd_prefix='os_pwd_'
  pwds=( admin_token mdsecret mysql_glance mysql_keystone mysql_nova \
         mysql_root ospwd_admin ospwd_demo ospwd_glance ospwd_nova )

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
  raw=$( ip addr list | grep -E '\s*inet 10.162.128.' 2> /dev/null | head -n1 )
  if [[ "$raw" =~ (([0-9]{1,3}\.){3}[0-9]{1,3}) ]] ; then   # fix color ))
    os_current_ip="${BASH_REMATCH[1]}"
  fi
  _e "current ip: $os_current_ip"
  _x [ "$os_current_ip" != '' ]

}

################################################################################
# HEAD NODE CONFIGURATION
################################################################################
function _i_head() {
  _e "*** head node part ***"

  _x _omnom mariadb-server MySQL-python qpid-cpp-server \
    openstack-keystone python-keystoneclient \
    openstack-glance python-glanceclient \
    openstack-nova-cert openstack-nova-conductor \
    openstack-nova-console openstack-nova-novncproxy openstack-nova-scheduler \
    python-novaclient

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

    _e "list of services"
    _x sudo -Eu nobody keystone service-list

    _e "exiting openstack admin environment"
  ) || exit $?

  # nova network (legacy, i.e. "old but gold")
  cf=/etc/nova/nova.conf
  _x openstack-config --set $cf DEFAULT network_api_class nova.network.api.API
  _x openstack-config --set $cf DEFAULT security_group_api nova

  # cat $cf | sed -e '/^$/d' | grep -v '^\s*#' | sed -e 's#^\[#\n[#'

  # start services at the end of everything

  # glance
  _x systemctl restart openstack-glance-api
  _x systemctl restart openstack-glance-registry
  _x systemctl enable openstack-glance-api
  _x systemctl enable openstack-glance-registry

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

    # initial network
    if [ "$os_novanet_mode" == 'vlan' ] ; then
      netid=$( sudo -Eu nobody nova net-list | grep -E '\|\s+flat-net\s+\|' | awk '{ print $2 }' )
      [ "$netid" != '' ] && _x sudo -Eu nobody nova net-delete "$netid"
      sudo -Eu nobody nova net-list | grep -qE '\|\s+vlan-net\s+\|' || \
        _x sudo -Eu nobody nova network-create vlan-net --multi-host T --fixed-range-v4 10.66.208.0/20 --vlan=806
    elif [ "$os_novanet_mode" == 'flat' ] ; then
      netid=$( sudo -Eu nobody nova net-list | grep -E '\|\s+vlan-net\s+\|' | awk '{ print $2 }' )
      [ "$netid" != '' ] && _x sudo -Eu nobody nova net-delete "$netid"
      sudo -Eu nobody nova net-list | grep -qE '\|\s+flat-net\s+\|' || \
        _x sudo -Eu nobody nova network-create flat-net --bridge=$os_brif --multi-host T --fixed-range-v4 10.162.208.0/20
    else
      _e "network type can be only 'flat' or 'vlan'"
      _x false
    fi

    _e "exiting openstack admin environment"
  ) || exit $?

}

################################################################################
# WORKER NODE CONFIGURATION
################################################################################
function _i_worker() {
  _e "*** worker node part ***"

  _x _omnom openstack-nova-compute openstack-nova-network \
    bridge-utils --disablerepo='slc6-*'

  ## network part ###

  _e "checking for phys iface ($os_physif), bridge ($os_brif) and mode ($os_novanet_mode)"
  _x [ "$os_physif" != '' ]
  _x [ "$os_brif" != '' ]
  _x [ "$os_novanet_mode" != '' ]

  # reset network to an initial state
  pref=/etc/sysconfig/network-scripts
  if [ "$os_novanet_mode" == 'flat' ] ; then
    _e 'configuring network as flat'
    if ! brctl show | grep -q "$os_brif" 2> /dev/null ; then

      _x systemctl stop network.service
      _e "creating bridge $os_brif with port $os_physif"

      # create the bridge
      cat > "${pref}/ifcfg-${os_brif}" <<EOF
DEVICE=${os_brif}
TYPE=Bridge
ONBOOT=Yes
BOOTPROTO=dhcp
PERSISTENT_DHCLIENT=1
IPV6INIT=no
EOF
      _x grep -q '^TYPE=Bridge$' "${pref}/ifcfg-${os_brif}"

      # make a backup
      mkdir -p "${pref}/openstack-backup"
      [ ! -e "${pref}/openstack-backup/ifcfg-$os_physif" ] && _x cp "$pref/ifcfg-$os_physif" "${pref}/openstack-backup/ifcfg-$os_physif"

      (
        grep -E '^\s*UUID=|^\s*HWADDR=|^\s*NAME=' "${pref}/openstack-backup/ifcfg-$os_physif" ;
        cat <<EOF
DEVICE=$os_physif
TYPE=Ethernet
BRIDGE=$os_brif
ONBOOT=yes
BOOTPROTO=none
USERCTL=no
PEERDNS=yes
DEFROUTE=no
PEERROUTES=yes
IPV4_FAILURE_FATAL=no
EOF
      ) > "${pref}/ifcfg-${os_physif}"
      _x grep -q '^TYPE=Ethernet$' "${pref}/ifcfg-${os_physif}"
      _x systemctl start network.service
    else
      _e "bridge $os_brif already configured"
    fi
  elif [ "$os_novanet_mode" == 'vlan' ] ; then
    _e 'configuring network as vlan'
    if brctl show | grep -q "$os_brif" 2> /dev/null ; then
      _x [ -e "${pref}/openstack-backup/ifcfg-${os_physif}" ]
      _x systemctl stop network.service
      _x rm -f "${pref}/ifcfg-${os_brif}"
      _x cp "${pref}/openstack-backup/ifcfg-${os_physif}" "${pref}/ifcfg-${os_physif}"
      _x systemctl start network.service
    else
      _e "no need to restore original interface $os_physif"
    fi

  else
    _e "network type can be only 'flat' or 'vlan'"
    _x false
  fi

  ## /network part ##

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

  # nova network (legacy)
  # --> http://docs.openstack.org/grizzly/openstack-compute/admin/content/configuring-vlan-networking.html
  # --> http://www.mirantis.com/blog/openstack-networking-flatmanager-and-flatdhcpmanager/
  _x openstack-config --set /etc/nova/nova.conf DEFAULT network_api_class nova.network.api.API
  _x openstack-config --set /etc/nova/nova.conf DEFAULT security_group_api nova
  _x openstack-config --set /etc/nova/nova.conf DEFAULT firewall_driver nova.virt.libvirt.firewall.IptablesFirewallDriver
  _x openstack-config --set /etc/nova/nova.conf DEFAULT network_size 4094
  _x openstack-config --set /etc/nova/nova.conf DEFAULT allow_same_net_traffic True
  _x openstack-config --set /etc/nova/nova.conf DEFAULT multi_host True
  _x openstack-config --set /etc/nova/nova.conf DEFAULT send_arp_for_ha True
  _x openstack-config --set /etc/nova/nova.conf DEFAULT share_dhcp_address True
  _x openstack-config --set /etc/nova/nova.conf DEFAULT force_dhcp_release True
  _x openstack-config --set /etc/nova/nova.conf DEFAULT public_interface $os_physif
  _x openstack-config --set /etc/nova/nova.conf DEFAULT flat_injected False

  if [ "$os_novanet_mode" == 'vlan' ] ; then
    _x openstack-config --set $cf DEFAULT network_manager nova.network.manager.VlanManager
    _x openstack-config --set $cf DEFAULT vlan_interface $os_physif
    _x openstack-config --del $cf DEFAULT flat_network_bridge
    _x openstack-config --del $cf DEFAULT flat_interface
  else
    _x openstack-config --set $cf DEFAULT network_manager nova.network.manager.FlatDHCPManager
    _x openstack-config --del $cf DEFAULT vlan_interface
    _x openstack-config --set $cf DEFAULT flat_network_bridge $os_brif
    _x openstack-config --set $cf DEFAULT flat_interface $os_physif
  fi

  # nova compute services
  _x systemctl restart libvirtd
  _x systemctl restart dbus
  _x systemctl restart openstack-nova-compute
  _x systemctl restart openstack-nova-network
  _x systemctl restart openstack-nova-metadata-api
  _x systemctl enable libvirtd
  _x systemctl enable dbus
  _x systemctl enable openstack-nova-compute
  _x systemctl enable openstack-nova-network
  _x systemctl enable openstack-nova-metadata-api

  # remove default virsh network
  if virsh net-info default > /dev/null 2>&1 ; then
    _x virsh net-destroy default
    _x virsh net-undefine default
  fi

}

################################################################################
# ENTRY POINT
################################################################################
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
