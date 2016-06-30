#!/bin/bash -e

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

rm -f /tmp/config.yaml
source $my_dir/functions

# provision machines
provision_machines 0 1 2 3

# prepare fuel master
prepare_fuel_master 0

# 3+1 cluster with default parameters:
#   zero-padding=false
#   TODO: add more parameters and check their default value
configure_cluster mode 1 primary-controller 1 compute 2,3

check_protection_domain 1 'default'
check_sp_name 1 'default'
check_path 1 'Device ' $device_paths
check_storage_pool 1 'Zero padding' 'disabled'
check_storage_pool 1 'Checksum mode' 'disabled'
check_storage_pool 1 'Background device scanner' 'Disabled'
check_storage_pool 1 'Spare policy' '10%'
check_capacity_alerts 1 '80' '90'
check_storage_pool 1 'Flash Read Cache' "Doesn't use"

remove_node_service 1 2 3
set_fuel_options protection-domain='pd'
set_fuel_options storage-pools='sp'
set_fuel_options password='Other_password'
set_fuel_options zero-padding='true'
set_fuel_options checksum-mode='true'
set_fuel_options scanner-mode='true'
set_fuel_options spare-policy='15'
set_fuel_options capacity-high-alert-threshold='79'
set_fuel_options capacity-critical-alert-threshold='89'
set_fuel_options cached-storage-pools='sp'
set_fuel_options rfcache-devices=$rfcache_path
configure_cluster mode 1 primary-controller 1 compute 2,3

check_password 1 'Other_password'
check_protection_domain 1 'pd'
check_sp_name 1 'sp'
check_storage_pool 1 'Zero padding' 'enabled'
check_storage_pool 1 'Checksum mode' 'enabled'
check_storage_pool 1 'Background device scanner' 'Mode: device_only'
check_storage_pool 1 'Spare policy' '15%'
check_capacity_alerts 1 '79' '89'
check_storage_pool 1 'Flash Read Cache' "Uses"
check_path 1 'Rfcache device ' $rfcache_path

save_logs
