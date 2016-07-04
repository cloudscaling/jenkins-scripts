#!/bin/bash -eux

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

source $my_dir/openrc
source /etc/environment
source $my_dir/functions-openstack

function exec_on_mdm() {
  $@
}

function get_provisioning_type() {
  awk '/provisioning_type:/ {print($2)}' /etc/astute.yaml
}

run_os_checks exec_on_mdm get_provisioning_type 
