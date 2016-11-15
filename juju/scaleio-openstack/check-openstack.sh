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

source $WORKSPACE/stackrc

create_virtualenv
run_os_checks exec_on_mdm get_provisioning_type
