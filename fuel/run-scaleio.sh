#!/bin/bash -ux

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

source ${my_dir}/fuel-utils

inner_script=${1:-}
if [ -z "$inner_script" ] ; then
  echo "No script is specified but required"
  exit 1
fi

clean_env=${CLEAN_ENV:-'true'}
fuel_version=${FUEL_VERSION:-'8.0'}
fuel_nodes=${FUEL_NODES:-6}

function save_logs() {
  nodes=`get_slave_nodes`
  for i in ${nodes}; do
    mkdir logs/$i
    execute_on_slave $i 'cat /var/log/fuel-plugin-scaleio.log' > logs/${i}/fuel-plugin-scaleio.log 2>/dev/null
    execute_on_slave $i 'cat /var/log/puppet.log' > logs/${i}/puppet.log 2>/dev/null
    if files=`execute_on_slave $i 'ls /var/log/nova/' 2>/dev/null` ; then
      for fl in $files ; do
        execute_on_slave $i "cat /var/log/nova/$fl" > logs/${i}/${fl} 2>/dev/null
      do
    fi
  done
  return 0
}

function destroy_env() {
  sudo /home/jenkins/fuel_ci/cleanup_env.sh
}

function catch_errors() {
  local exit_code=$?
  echo "Line: $1  Error=$exit_code  Command: '$BASH_COMMAND'"
  # disable error trap
  trap - ERR
  # sleep some time to flush logs
  save_logs
  destroy_env
  exit $exit_code
}

trap 'catch_errors $LINENO' ERR

rm -rf logs
mkdir logs

if [[ $clean_env != 'false' ]] ; then
  #TODO: use provisioning from fuel-qa/fuel-devops or somthing like that
  sudo /home/jenkins/fuel_ci/cleanup_env.sh
  sudo /home/jenkins/fuel_ci/provision_fuel.sh "MirantisOpenStack-${fuel_version}.iso" ${fuel_nodes}
else
  #TODO: add check fuel_version in existing environment
  echo WARN: check of version should be added in case of non-clean env
fi

$my_dir/$inner_script

save_logs
destroy_env
trap - ERR
