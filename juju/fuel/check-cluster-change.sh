#!/bin/bash -eu

# set this flag to true because fuel-plugin-scaleio is from master branch and dependent puppets also should be last version
export PUPPET_DEV_MODE='true'

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

source $my_dir/functions

# provision machines
provision_machines 0 1 2 3 4 5 6 7

# prepare fuel master
prepare_fuel_master 0

echo "INFO: Configuring 1+2 cluster"
configure_cluster mode 1 primary-controller 1 compute 2,3

echo "INFO: Configuring 2+2 cluster"
configure_cluster mode 1 primary-controller 1 compute 2,3 controller 4

echo "INFO: 1->3 mode cluster"
configure_cluster mode 3 primary-controller 1 compute 2,3 controller 4,5

echo "INFO: 3->1 mode cluster"
remove_node_service 1
configure_cluster mode 1 primary-controller 4 compute 2,3 controller 5

echo "INFO: 1->3 mode cluster"
configure_cluster mode 3 primary-controller 4 compute 2,3 controller 1,5

echo "INFO: Configuring 4+2 cluster"
configure_cluster mode 3 primary-controller 4 compute 2,3 controller 1,5,6

echo "INFO: 3->5 mode cluster"
configure_cluster mode 5 primary-controller 4 compute 2,3 controller 1,5,6,7

echo "INFO: 5->3 mode cluster"
remove_node_service 4
configure_cluster mode 3 primary-controller 1 compute 2,3 controller 5,6,7

echo "INFO: Configuring 3+2 cluster"
remove_node_service 5
configure_cluster mode 3 primary-controller 1 compute 2,3 controller 6,7

echo "INFO: Configuring 3+1 cluster"
remove_node_service 3
configure_cluster mode 3 primary-controller 1 compute 2 controller 6,7

echo "INFO: 3->5 mode cluster"
configure_cluster mode 5 primary-controller 1 compute 2,3 controller 4,5,6,7

echo "INFO: 5->1 mode cluster"
mdms=''
for node in 1 4 5 6 7 ; do
  mdms+="${machines[$node]} "
done
current_master_mdm=`get_master_mdm "echo $mdms"`
cluster_output=`juju-ssh $current_master_mdm "sudo scli --query_cluster --approve_certificate" 2>/dev/null`
slave_mdms_ip=(`echo "$cluster_output" | grep -A 10 "Slave MDMs:" | grep "Name:" | head -2 | awk '{gsub("[^0-9.]","",$2); print $2}'`)
tie_breakers_ip=(`echo "$cluster_output" | grep -A 10 "Tie-Breakers:" | grep "Name:" | head -2 | awk '{gsub("[^0-9.]","",$2); print $2}'`)
slave_mdms=()
tie_breakers=()

for mdm in 1 4 5 6 7 ; do
  mdm_ip=`juju-ssh ${machines[$mdm]} "ifconfig" 2>/dev/null | awk '/inet addr:/{print $2}' | head -1 | sed 's/addr://g'`
  if [[ ${machines[$mdm]} == $current_master_mdm ]] ; then
    current_master_mdm_index=$mdm
  elif [[ ${slave_mdms_ip[@]} =~ $mdm_ip ]] ; then
    slave_mdms+=($mdm)
  elif [[ ${tie_breakers_ip[@]} =~ $mdm_ip ]] ; then
    tie_breakers+=($mdm)
  fi
done

# 1+2 cluster
remove_node_service $current_master_mdm_index ${slave_mdms[1]}
new_master_mdm=${slave_mdms[0]}
configure_cluster mode 1 primary-controller $new_master_mdm compute 2,3

echo "INFO: 1->5 mode cluster"
configure_cluster mode 5 primary-controller $new_master_mdm compute 2,3 controller $current_master_mdm_index,${slave_mdms[1]},${tie_breakers[0]},${tie_breakers[1]}


echo "INFO: Basic deploy 3+2 cluster"
remove_node_service 1 2 3 4 5 6 7
configure_cluster mode 3 primary-controller 1 compute 2,3 controller 4,5

echo "INFO: Basic deploy 5+2 cluster"
remove_node_service 1 2 3 4 5
configure_cluster mode 5 primary-controller 1 compute 2,3 controller 4,5,6,7

save_logs
