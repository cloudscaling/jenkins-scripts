#!/bin/bash -e

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

source $my_dir/functions

# provision machines
provision_machines 0 1 2 3 4 5 6 7

# prepare fuel master
prepare_fuel_master 0

# 3+1 cluster with default parameters:
configure_cluster mode 1 primary-controller 1 compute 2,3
# Adding compute node to check that it will get to the same protection domain (parameter protection-domain-nodes is 100 by default)
configure_cluster mode 1 primary-controller 1 compute 2,3,4

check_fuel_performance 1
check_protection_domain 1 'default'
check_protection_domain_nodes 1 '100'
check_sds_storage_pool 1 'default' "$device_paths"
check_storage_pool 1 'Zero padding' 'disabled'
check_storage_pool 1 'Checksum mode' 'disabled'
check_storage_pool 1 'Background device scanner' 'Disabled'
check_storage_pool 1 'Spare policy' '10%'
check_capacity_alerts 1 '80' '90'
check_storage_pool 1 'Flash Read Cache' "Doesn't use"
check_sds_on_controller 1 'true'

remove_node_service 1 2 3 4

set_fuel_options metadata-enabled='false'
configure_cluster mode 1 primary-controller 1 compute 2
check_scaleio_not_installed 1
remove_node_service 1 2

new_storage_pools='sp1,sp2'
new_device_paths='/dev/xvdf,/dev/xvdg'

set_fuel_options metadata-enabled='true'
set_fuel_options protection-domain='pd'
set_fuel_options protection-domain-nodes='3'
set_fuel_options storage-pools=$new_storage_pools
set_fuel_options device-paths=$new_device_paths
set_fuel_options password='Other_password'
set_fuel_options zero-padding='true'
set_fuel_options checksum-mode='true'
set_fuel_options scanner-mode='true'
set_fuel_options spare-policy='15'
set_fuel_options capacity-high-alert-threshold='79'
set_fuel_options capacity-critical-alert-threshold='89'
set_fuel_options cached-storage-pools='sp2'
set_fuel_options rfcache-devices=$rfcache_paths
set_fuel_options sds-on-controller='false'
configure_cluster mode 1 primary-controller 1 compute 2,3,4
configure_cluster mode 1 primary-controller 1 compute 2,3,4,5,6,7

check_password 1 'Other_password'
check_protection_domain 1 'pd'
check_protection_domain_nodes 1 '3'
check_sds_storage_pool 1 "$new_storage_pools" "$new_device_paths"
check_storage_pool 1 'Zero padding' 'enabled'
check_storage_pool 1 'Checksum mode' 'enabled'
check_storage_pool 1 'Background device scanner' 'Mode: device_only'
check_storage_pool 1 'Spare policy' '15%'
check_capacity_alerts 1 '79' '89'
check_specific_storage_pool 1 'Flash Read Cache' "Uses" 'sp2'
check_rfcache 1 "$rfcache_paths"
check_sds_on_controller 1 'false'

save_logs
