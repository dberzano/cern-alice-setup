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
        nova=( \
          openstack-nova-api openstack-nova-cert openstack-nova-consoleauth \
          openstack-nova-scheduler openstack-nova-conductor \
          openstack-nova-novncproxy )
      ;;
      --worker)
        aux=( libvirtd dbus )
        auth=()
        glance=()
        nova=( openstack-nova-compute  )
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
      --all)    services='all' ;;
      --aux)    services='aux' ;;
      --auth)   services='auth' ;;
      --glance) services='glance' ;;
      --nova)   services='nova' ;;
      *)
        _e "unknown param: $1"
        exit 1
      ;;
    esac
    shift
  done

  srv=''
  case "$services" in
    all)    srv="${aux[@]} ${auth[@]} ${glance[@]} ${nova[@]}" ;;
    aux)    srv="${aux[@]}" ;;
    glance) srv="${glance[@]}" ;;
    nova)   srv="${nova[@]}" ;;
    *)      srv="${auth[@]} ${glance[@]} ${nova[@]}" ;;
  esac

  if [ "$(echo ${srv[*]})" == '' ] ; then
    _e "use --worker or --head to select pertaining services"
    exit 1
  fi

  if [ "$action" == 'restart' ] || [ "$action" == 'stop' ] ; then
    _e "the following services will be affected:"
    for s in ${srv[@]} ; do
      _e " * $s"
    done
    _e "proceed? (type yes)"
    read ans
    if [ "$ans" != 'yes' ] ; then
      _e "aborting"
      exit 1
    fi
  fi

  for s in ${srv[@]} ; do
    case "$action" in
      restart)
        systemctl restart $s
        _status $s
      ;;
      stop)
        systemctl stop $s
        _status $s
      ;;
      *)
        _status $s
      ;;
    esac
  done

  return 1

}

_m "$@" || exit $?
