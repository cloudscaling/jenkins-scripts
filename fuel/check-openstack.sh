#!/bin/bash -ex

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

source $my_dir/openrc
source /etc/environment
source $my_dir/functions-openstack

retry_limit=3

function exec_on_mdm() {
  bash -c "$@"
}

function exec_on_mdm_with_retry () {
  count=1
  while ! exec_on_mdm "$@" ; do
    echo "INFO: try ${count} faled (cmd: ${@})"
    if [[ $count == $retry_limit ]] ; then
      echo 'ERROR: number of retries is exceeded'
      return 1
    fi
    sleep 1
    (( ++count ))
  done
}

function get_provisioning_type() {
  awk '/provisioning_type:/ {print($2)}' /etc/astute.yaml 2>/dev/null
}

export SCALEIO_PROTECTION_DOMAIN='default'
run_os_checks exec_on_mdm_with_retry get_provisioning_type
