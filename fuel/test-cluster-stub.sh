#!/bin/bash -e

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

source ${my_dir}/fuel-utils

copy_to_master "${my_dir}/*.sh"
copy_to_master "${my_dir}/*.py"
execute_on_master './prepare_plugin.sh'
execute_on_master './cluster.sh'
