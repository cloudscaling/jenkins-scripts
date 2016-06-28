#!/bin/bash -e

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"


#TODO: change it after reuse of other provisioning:
fuel_master='10.20.0.2'
scp -o StrictHostKeyChecking=no ${my_dir}/*.sh root@${fuel_master}:/root/
scp -o StrictHostKeyChecking=no ${my_dir}/*.py root@${fuel_master}:/root/
ssh -o StrictHostKeyChecking=no root@${fuel_master} '~/prepare_plugin.sh'
ssh -o StrictHostKeyChecking=no root@${fuel_master} '~/test-cluster.sh'
