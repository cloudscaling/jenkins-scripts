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
check_storage_pool 1 'Checksum mode' 'disabled'
check_storage_pool 1 'Background device scanner' 'Disabled'
check_storage_pool 1 'Spare policy' '10%'
check_capacity_alerts 1 '80' '90'
check_storage_pool 1 'Flash Read Cache' "Doesn't use"

remove_node_service 1 2 3

#TODO: add more key=value in set_fuel_options for more parameters with different (from default_ values)
set_fuel_options zero-padding=true
set_fuel_options checksum-mode=true
set_fuel_options scanner-mode=true
set_fuel_options spare-policy=15
set_fuel_options capacity-high-alert-threshold=79
set_fuel_options capacity-critical-alert-threshold=89
set_fuel_options cached-storage-pools=default
set_fuel_options rfcache-devices=/dev/xvdg
configure_cluster mode 1 primary-controller 1 compute 2,3

check_storage_pool 1 'Zero padding' 'enabled'
check_storage_pool 1 'Checksum mode' 'enabled'
check_storage_pool 1 'Background device scanner' 'Mode: device_only'
check_storage_pool 1 'Spare policy' '15%'
check_capacity_alerts 1 '79' '89'
check_storage_pool 1 'Flash Read Cache' "Uses"
check_cache 1 '/dev/xvdg'

save_logs
