#!/bin/bash -eux

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
remove_node_service 4 5 6 7
configure_cluster mode 1 primary-controller 1 compute 2,3

# 5+2 cluster
configure_cluster mode 5 primary-controller 1 compute 2,3 controller 4,5,6,7

# basic deploy 3+2 cluster
remove_node_service 1,2,3,4,5,6
configure_cluster mode 3 primary-controller 1 compute 2,3 controller 4,5

# basic deploy 5+2 cluster
remove_node_service 1,2,3,4,5
configure_cluster mode 5 primary-controller 1 compute 2,3 controller 4,5,6,7

save_logs
