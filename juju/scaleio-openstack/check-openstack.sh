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

echo "Master MDM found at $master_mdm"
auth_ip=`juju status keystone/0 --format json | jq .services.keystone.units | grep public-address | sed 's/[\",]//g' | awk '{print $2}'`
export OS_AUTH_URL=http://$auth_ip:5000/v2.0
export OS_USERNAME=admin
export OS_TENANT_NAME=admin
export OS_PROJECT_NAME=admin
export OS_PASSWORD=password

create_virtualenv
run_os_checks exec_on_mdm get_provisioning_type
