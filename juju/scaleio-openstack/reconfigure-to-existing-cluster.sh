#!/bin/bash -e

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

source $my_dir/../functions
source $my_dir/functions

echo "INFO: Checing use_existing_cluster feature"
echo "INFO: Reconfigure cluster to two clusters: ScaleIO and OpenStack. Link them via scaleio-cluster charm."

echo "INFO: Remove SDC-MDM and GW-OpenStack relations."
juju remove-relation scaleio-sdc scaleio-mdm
juju remove-relation scaleio-openstack scaleio-gw

echo "INFO: Deploy Scaleio Cluster charm"
juju deploy --repository juju-scaleio local:scaleio-cluster --to 0

ip=`juju status scaleio-gw | grep public-address | awk '{print $2}'`
port=`get_config scaleio-gw port`
user='scaleio_client'
password="$(tr -dc A-Za-z0-9 < /dev/urandom | head -c${1:-8})_$(tr -dc A-Za-z0-9 < /dev/urandom | head -c${1:-8})"

mdm=`get_master_mdm`
output=`juju ssh $mdm "scli --approve_certificate --login --username $USERNAME --password $PASSWORD && scli --reset_password --username $user" 2>/dev/null | grep 'Password reseted' | sed $'s/\r//'`
new_password=`echo $output | grep -o " '[a-zA-Z0-9]*'$" | xargs`
juju ssh $mdm "scli --approve_certificate --login --username $user --password $new_password && scli --set_password --old_password $new_password --new_password $password" 2>/dev/null

juju set scaleio-cluster gateway-ip="$ip" gateway-port="$port" gateway-user="$user" gateway-password="$password"

echo "INFO: Add relations"
juju add-relation "scaleio-sdc:scaleio-mdm" "scaleio-cluster:scaleio-mdm"
juju add-relation "scaleio-openstack:scaleio-gw" "scaleio-cluster:scaleio-gw"

echo "INFO: Wait for services start: $(date)"
wait_absence_status_for_services "executing|blocked|waiting|allocating"
echo "INFO: Wait for services end: $(date)"

# check for errors
if juju status | grep "current" | grep error ; then
  echo "ERROR: Some services went to error state"
  juju ssh 0 sudo grep Error /var/log/juju/all-machines.log 2>/dev/null
  exit 1
fi
