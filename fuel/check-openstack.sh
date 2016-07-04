#!/bin/bash -ex

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

source $my_dir/openrc
source /etc/environment
source $my_dir/functions-openstack

function exec_on_mdm() {
  bash -c "$@"
}

function get_provisioning_type() {
  type=`awk '/provisioning_type:/ {print($2)}' /etc/astute.yaml` 2>/dev/null
  if [[ "${type}" != 'thin' ]] ; then
    echo Thick
  else
    echo Thin
  fi
}

easy_install pip
pip install -q virtualenv

run_os_checks exec_on_mdm get_provisioning_type 
