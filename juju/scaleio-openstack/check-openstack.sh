#!/bin/bash -e

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

source $my_dir/../functions
source $my_dir/../functions-openstack

master_mdm=`get_master_mdm`

function exec_on_mdm() {
  juju-ssh $master_mdm "$@"
}

function get_provisioning_type() {
  juju-get scaleio-openstack provisioning-type
}

echo "INFO: Master MDM found at $master_mdm"
auth_ip=`get_machine_ip keystone`
export OS_AUTH_URL=http://$auth_ip:5000/v2.0
export OS_USERNAME=admin
export OS_TENANT_NAME=admin
export OS_PROJECT_NAME=admin
export OS_PASSWORD=password

create_virtualenv
run_os_checks exec_on_mdm get_provisioning_type
