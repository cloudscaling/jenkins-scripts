#!/bin/bash -e

# set this flag to true because fuel-plugin-scaleio is from master branch and dependent puppets also should be last version
export PUPPET_DEV_MODE='true'

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

source $my_dir/functions

# provision machines
provision_machines 0 1 2 3 4

# prepare fuel master
prepare_fuel_master 0

echo ""
echo "Deploying 3+1 cluster with default parameters"
configure_cluster mode 1 primary-controller 1 compute 2,3
# Adding compute node to check that it will get to the same protection domain (parameter protection-domain-nodes is 100 by default)
configure_cluster mode 1 primary-controller 1 compute 2,3,4

check_branch 1
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
check_storage_pool 1 'RAM Read Cache' "Doesn't use"
check_sds_on_controller 1 'true'
check_hyper_converged_deployment 1,2,3,4

remove_node_service 1 2 3 4

echo ""
echo "Deploying cluster with metadata-enabled=false (cluster shouldn't be installed)"
set_fuel_options metadata-enabled='false'
configure_cluster mode 1 primary-controller 1 compute 2
check_scaleio_not_installed 1
remove_node_service 1 2

# Deploy bundle
echo ""
echo "Deploying with existing cluster"
$my_dir/../scaleio/deploy-scaleio-cluster.sh

gateway_ip=`juju status scaleio-gw | grep public-address | awk '{print $2}'`

set_fuel_options metadata-enabled='true'
set_fuel_options existing-cluster="true"
set_fuel_options gateway-ip=$gateway_ip
set_fuel_options gateway-port="4443"
set_fuel_options gateway-user="admin"
set_fuel_options password="Default_password"
configure_cluster primary-controller 1 compute 2,3

check_existing_cluster 1,2,3

juju remove-service scaleio-sds
juju remove-service scaleio-mdm
juju remove-service scaleio-gw
remove_node_service 1 2 3
wait_for_removed "scaleio-sds"
wait_for_removed "scaleio-mdm"
wait_for_removed "scaleio-gw"

echo ""
echo "Deploying cluster with changed parameters"
provision_machines 5 6 7 8

new_storage_pools='sp1,sp2'
new_device_paths='/dev/xvdf,/dev/xvdg'

set_fuel_options existing-cluster="false"
set_fuel_options gateway-ip=""
set_fuel_options gateway-port="4443"
set_fuel_options gateway-user="admin"
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
set_fuel_options rmcache-usage='true'
set_fuel_options rmcache-passthrough-pools='sp1,sp2'
set_fuel_options sds-on-controller='false'
set_fuel_options hyper-converged-deployment='false'

configure_cluster mode 1 primary-controller 1 compute 2 scaleio 3,4,5
configure_cluster mode 1 primary-controller 1 compute 2 scaleio 3,4,5,6,7,8

check_password 1 'Other_password'
check_protection_domain 1 'pd'
check_protection_domain_nodes 1 '3'
check_sds_ip_roles 1 "All (SDS and SDC)"
check_sds_storage_pool 1 "$new_storage_pools" "$new_device_paths"
check_storage_pool 1 'Zero padding' 'enabled'
check_storage_pool 1 'Checksum mode' 'enabled'
check_storage_pool 1 'Background device scanner' 'Mode: device_only'
check_storage_pool 1 'Spare policy' '15%'
check_capacity_alerts 1 '79' '89'
check_specific_storage_pool 1 'Flash Read Cache' "Uses" 'sp2'
check_specific_storage_pool 1 'RAM Read Cache' "Uses" 'sp1,sp2'
check_specific_storage_pool 1 'write handling mode' "passthrough" 'sp1,sp2'
check_rfcache 1 "$rfcache_paths"
check_sds_on_controller 1 'false'
check_hyper_converged_deployment 3,4,5,6,7,8

echo ""
echo "Deploying cluster for testing protection domain nodes limit, rmcache, sds ip roles"
for node in ${machines[@]} ; do
  create_eth1 $node
  juju ssh $node "sudo ip addr add 10.0.123.$node/24 dev eth1" 2>/dev/null
done

remove_node_service 1 2 3 4 5 6 7 8
storage_iface='eth1'
set_fuel_options protection-domain-nodes='3'
set_fuel_options rmcache-usage='true'
set_fuel_options rmcache-passthrough-pools='sp1'
set_fuel_options rmcache-cached-pools='sp2'
set_fuel_options hyper-converged-deployment='true'
configure_cluster mode 1 primary-controller 1 compute 2,3,4,5,6,7

check_sds_ip_roles 1 "SDS Only"
check_sds_ip_roles 1 "SDC Only"
check_protection_domain_nodes 1 '3'
check_specific_storage_pool 1 'RAM Read Cache' "Uses" 'sp1,sp2'
check_specific_storage_pool 1 'write handling mode' "cached" 'sp2'
check_specific_storage_pool 1 'write handling mode' "passthrough" 'sp1'
check_hyper_converged_deployment 2,3,4,5,6,7

save_logs
