#!/bin/bash -e

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

source $my_dir/../functions
source $my_dir/../functions-openstack

master_mdm=`get_master_mdm`

function exec_on_mdm() {
  juju ssh $master_mdm "$@"
}

function get_provisioning_type() {
  juju get scaleio-openstack | grep -A 15 provisioning-type | grep "value:" | head -1 | awk '{print $2}'
}

function get_volume_by_instance() {
  instance="$1"

  nodes=`juju status nova-compute --format tabular | awk '/nova-compute\//{print $5}'`
  for node in $nodes ; do
    if ! output=`juju ssh $node "virsh domblklist $instance" 2>/dev/null` ; then
      continue
    fi
    vol_id=`echo "$output" | grep -Po "emc-vol-[0-9a-zA-Z]*-[0-9a-zA-Z]*" | cut -d '-' -f 4`
    echo $vol_id
    return 0
  done

  return 1
}

echo "INFO: Master MDM found at $master_mdm"
auth_ip=`juju status keystone --format tabular | awk '/keystone\/0/{print $7}'`
export OS_AUTH_URL=http://$auth_ip:5000/v2.0
export OS_USERNAME=admin
export OS_TENANT_NAME=admin
export OS_PROJECT_NAME=admin
export OS_PASSWORD=password

create_virtualenv
run_os_checks exec_on_mdm get_provisioning_type get_volume_by_instance
