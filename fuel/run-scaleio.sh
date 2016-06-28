#!/bin/bash -eux


my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

inner_script=${1:-}
if [ -z "$inner_script" ] ; then
  echo "No script is specified but required"
  exit 1
fi

function save_logs() {
  #TODO: save logs from fuel nodes
  return 0
}

function destroy_env() {
  if [[ $CLEAN_ENV != 'false' ]] ; then
    #TODO: delete fuel VMs
    return 0
  fi
  return 0
}

function catch_errors() {
  local exit_code=$?
  echo "Line: $1  Error=$exit_code  Command: '$BASH_COMMAND'"
  # sleep some time to flush logs
  save_logs
  destroy_env
  exit $exit_code
}

#TODO: use provisioning from fuel-qa/fuel-devops or somthing like that
if ! sudo /home/jenkins/fuel_ci/provision_fuel.sh "MirantisOpenStack-${FUEL_VERSION}.iso" ${FUEL_NODES} ; then
  echo "Provisioning error. exiting..."
  exit 1
fi

trap 'catch_errors $LINENO' ERR

rm -rf logs
mkdir logs

$my_dir/$inner_script

save_logs
destroy_env
trap - ERR
