#!/bin/bash -ex

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

source ${my_dir}/fuel-utils

controller_node=`get_controller_nodes | head -n 1`
copy_no_slave $controller_node "${my_dir}/check-openstack.sh ${my_dir}/../juju/functions-openstack"
execute_on_slave $controller_node "./check-openstack.sh"
