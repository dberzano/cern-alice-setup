#!/bin/bash

export LANG=C

function _d() {
  date +%Y%m%d-%H%M%S
}

function _e() {
  echo -e "\033[34m$1\033[m" >&2
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

function _status() {
  systemctl status $s > /dev/null 2>&1
  if [ $? == 0 ] ; then
    echo -e "\033[34m[\033[32m up \033[34m] $s\033[m"
  else
    echo -e "\033[34m[\033[31mdown\033[34m] $s\033[m"
  fi
}

function _m() {

  if [ `whoami` != 'root' ] ; then
    _e "you must be root to manage services: exiting"
    return 1
  fi

  while [ $# -gt 0 ] ; do
    case "$1" in
      --head)
        aux=( mysqld qpidd )
        auth=( openstack-keystone )
        glance=( openstack-glance-api openstack-glance-registry )
        neutron=( neutron-server neutron-metadata-agent \
          neutron-openvswitch-agent neutron-dhcp-agent \
          neutron-l3-agent openvswitch )
        nova=( \
          openstack-nova-api openstack-nova-cert openstack-nova-consoleauth \
          openstack-nova-scheduler openstack-nova-conductor \
          openstack-nova-novncproxy )
        novanet=()
        ok=1
      ;;
      --worker)
        aux=( libvirtd dbus )
        auth=()
        glance=()
        neutron=( neutron-openvswitch-agent openvswitch )
        nova=( openstack-nova-compute )
        novanet=( openstack-nova-network openstack-nova-metadata-api )
        ok=1
      ;;
      --status)
        action='status'
      ;;
      --restart)
        action='restart'
      ;;
      --stop)
        action='stop'
      ;;
      --all|--aux|--auth|--glance|--neutron|--nova|--novanet) services="${1:2}" ;;
      *)
        _e "unknown param: $1"
        exit 1
      ;;
    esac
    shift
  done

  srv=''
  case "$services" in
    all)     srv="${aux[@]} ${auth[@]} ${glance[@]} ${novanet[@]} ${nova[@]}" ;;
    aux)     srv="${aux[@]}" ;;
    glance)  srv="${glance[@]}" ;;
    neutron) srv="${neutron[@]}" ;;
    novanet) srv="${novanet[@]}" ;;
    nova)    srv="${nova[@]}" ;;
    *)       srv="${auth[@]} ${glance[@]} ${novanet[@]} ${nova[@]}" ; services='os' ;;
  esac

  if [ "$services" == '' ] || [ "$ok" != 1 ] ; then
    _e "usage: $0 [--worker|--head] [--all|--aux|--auth|--glance|--neutron|--nova|--novanet] [--restart|--stop]"
    exit 1
  fi

  if [ "$action" == 'restart' ] || [ "$action" == 'stop' ] ; then
    _e "the following services will be affected:"
    for s in ${srv[@]} ; do
      _e " * $s"
    done
    _e ">> press 'y' to proceed <<"
    read -n1 ans
    _e ''
    if [ "$ans" != 'y' ] && [ "$ans" != 'Y' ] ; then
      _e "cancelled"
      exit 1
    fi
  fi

  for s in ${srv[@]} ; do
    case "$action" in
      restart)
        echo -en "\033[34m[\033[35m....\033[34m] $s\033[m"
        systemctl restart $s
        sleep 1
        echo -en '\r'
        _status $s
      ;;
      stop)
        echo -en "\033[34m[\033[35m....\033[34m] $s\033[m"
        systemctl stop $s
        echo -en '\r'
        _status $s
      ;;
      *)
        action='status'
        _status $s
      ;;
    esac
  done

  if [ "$action" == 'status' ] ; then
    ni=$( virsh list 2> /dev/null | grep -cE '\s+instance-' )
    _e "number of instances: \033[32m$ni"
  fi

  return 1

}

_m "$@" || exit $?
