#!/bin/bash -eux

# set this flag to true because fuel-plugin-scaleio is from master branch and dependent puppets also should be last version
export PUPPET_DEV_MODE='true'

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

source $my_dir/functions

# provision machines
provision_machines 0 1 2 3 4 5 6 7

# prepare fuel master
prepare_fuel_master 0

# 1+2 cluster
configure_cluster mode 1 primary-controller 1 compute 2,3

# 2+2 cluster
configure_cluster mode 1 primary-controller 1 compute 2,3 controller 4

# 3+2 cluster
configure_cluster mode 3 primary-controller 1 compute 2,3 controller 4,5

# 2+2 cluster
remove_node_service 1
configure_cluster mode 1 primary-controller 4 compute 2,3 controller 5

# 3+2 cluster
configure_cluster mode 3 primary-controller 4 compute 2,3 controller 1,5

# 4+2 cluster
configure_cluster mode 3 primary-controller 4 compute 2,3 controller 1,5,6

# 5+2 cluster
configure_cluster mode 5 primary-controller 4 compute 2,3 controller 1,5,6,7

# 4+2 cluster
remove_node_service 4
configure_cluster mode 3 primary-controller 1 compute 2,3 controller 5,6,7

# 3+2 cluster
remove_node_service 5
configure_cluster mode 3 primary-controller 1 compute 2,3 controller 6,7

# 3+1 cluster
remove_node_service 3
configure_cluster mode 3 primary-controller 1 compute 2 controller 6,7

# 5+2 cluster
configure_cluster mode 5 primary-controller 1 compute 2,3 controller 4,5,6,7

# 1+2 cluster
echo "INFO: Switching cluster mode from 5 to 1"
master_mdm=1
cluster_output=`juju ssh ${machines[$master_mdm]} "sudo scli --query_cluster --approve_certificate" 2>/dev/null`
slave_mdms_ip=(`echo "$cluster_output" | grep -A 10 "Slave MDMs:" | grep "Name:" | head -2 | awk '{gsub("[^0-9.]","",$2); print $2}'`)
tie_breakers_ip=(`echo "$cluster_output" | grep -A 10 "Tie-Breakers:" | grep "Name:" | head -2 | awk '{gsub("[^0-9.]","",$2); print $2}'`)
slave_mdms=()
tie_breakers=()

for mdm in 4 5 6 7 ; do
  machine=${machines[$mdm]}
  mdm_ip=`juju ssh $machine "ifconfig" 2>/dev/null | awk '/inet addr:/{print $2}' | head -1 | sed 's/addr://g'`
  if [[ ${slave_mdms_ip[@]} =~ $mdm_ip ]] ; then
    slave_mdms+=($mdm)
  elif [[ ${tie_breakers_ip[@]} =~ $mdm_ip ]] ; then
    tie_breakers+=($mdm)
  fi
done

# 1+2 cluster
remove_node_service 1 ${slave_mdms[1]}
new_master_mdm=${slave_mdms[0]}
configure_cluster mode 1 primary-controller $new_master_mdm compute 2,3
remove_node_service ${tie_breakers[@]}

# 5+2 cluster
configure_cluster mode 5 primary-controller $new_master_mdm compute 2,3 controller 1,${slave_mdms[1]},${tie_breakers[0]},${tie_breakers[1]}


# basic deploy 3+2 cluster
remove_node_service 1 2 3 4 5 6 7
configure_cluster mode 3 primary-controller 1 compute 2,3 controller 4,5

# basic deploy 5+2 cluster
remove_node_service 1 2 3 4 5
configure_cluster mode 5 primary-controller 1 compute 2,3 controller 4,5,6,7

save_logs
