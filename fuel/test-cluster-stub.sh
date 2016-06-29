#!/bin/bash -e

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"


#TODO: change it after reuse of other provisioning:
fuel_master='10.20.0.2'
ssh_opts='-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null'
scp ${ssh_opts} ${my_dir}/*.sh root@${fuel_master}:/root/
scp ${ssh_opts} ${my_dir}/*.py root@${fuel_master}:/root/
ssh ${ssh_opts} root@${fuel_master} 'cd /root && ./prepare_plugin.sh'
ssh ${ssh_opts} root@${fuel_master} 'cd /root && ./test-cluster.sh'
