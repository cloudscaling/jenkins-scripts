#!/bin/bash -e

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

source $my_dir/functions


# provision machines
provision_machines 0 1 2 3

# prepare fuel master
prepare_fuel_master 0

# 3+1 cluster with default parameters:
#   zero-padding=false
#   TODO: add more parameters and check their default value
configure_cluster mode 1 primary-controller 1 compute 2,3
check_storage_pool 1 'Zero padding' 'disabled'   

remove_node_service 1 2 3 4
#TODO: add more key=value in set_fuel_options for more parameters with different (from default_ values)
set_fuel_options zero-padding=true
configure_cluster mode 1 primary-controller 1 compute 2,3
check_storage_pool 1 'Zero padding' 'enabled'   


save_logs
