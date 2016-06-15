#!/bin/bash -e

source functions

# provision machines
provision_machines 0 1 2 3 4

# prepare fuel master
prepare_fuel_master 0

# 3+1 cluster
configure_cluster mode 3 primary-controller 1,2,3 compute 4

save_logs
