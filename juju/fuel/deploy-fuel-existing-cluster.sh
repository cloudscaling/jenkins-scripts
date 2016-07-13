#!/bin/bash -e

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

source $my_dir/functions

# Deploy bundle
$my_dir/../scaleio/deploy-scaleio-cluster.sh

# provision machines
provision_machines 0 1 2 3
# prepare fuel master
prepare_fuel_master 0

gateway_ip=`juju status scaleio-gw | grep public-address | awk '{print $2}'`

set_fuel_options existing-cluster="true"
set_fuel_options gateway-ip=$gateway_ip
set_fuel_options gateway-port="4443"
set_fuel_options gateway-user="admin"
set_fuel_options password="Default_password"
configure_cluster primary-controller 1 compute 2,3

check_existing_cluster 1,2,3
