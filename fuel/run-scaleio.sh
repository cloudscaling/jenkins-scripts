#!/bin/bash -ux

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

source ${my_dir}/fuel-utils

inner_script=${1:-}
if [ -z "$inner_script" ] ; then
  echo "No script is specified but required"
  exit 1
fi

clean_env=${CLEAN_ENV:-'auto'}
fuel_version=${FUEL_VERSION:-'10.0'}
fuel_nodes=${FUEL_NODES:-6}

function save_logs() {
  nodes=`get_slave_nodes`
  for i in ${nodes}; do
    mkdir -p logs/$i
    execute_on_slave $i 'cat /var/log/fuel-plugin-scaleio.log' > logs/${i}/fuel-plugin-scaleio.log 2>/dev/null
    execute_on_slave $i 'cat /var/log/puppet.log' > logs/${i}/puppet.log 2>/dev/null
    for dr in '/var/log/nova/' '/etc/nova/' ; do
      execute_on_slave $i "ls -l $dr"
      if files=`execute_on_slave $i "ls $dr" 2>/dev/null` ; then
        for fl in $files ; do
          execute_on_slave $i "cat ${dr}${fl}" > logs/${i}/${fl}
        done
      fi
    done
  done
  return 0
}

function destroy_env() {
  local step=$1
  local do_cleanup='false'
  case $clean_env in
    "auto")
      if [[ $step == 'before' || $step == 'after' ]] ; then
        do_cleanup='true'
      fi
      ;;
    "before_only")
      if [[ $step == 'before' ]] ; then
        do_cleanup='true'
      fi
      ;;
  esac
  if [[ $do_cleanup != 'false' ]] ; then
    sudo ${my_dir}/cleanup_env.sh
  else
    echo Skip destroy env
  fi
}

function catch_errors() {
  local exit_code=$?
  echo "Line: $1  Error=$exit_code  Command: '$BASH_COMMAND'"
  # disable error trap
  trap - ERR
  # sleep some time to flush logs
  save_logs
  destroy_env 'error'
  exit $exit_code
}

trap 'catch_errors $LINENO' ERR

rm -rf logs
mkdir logs

#TODO: use provisioning from fuel-qa/fuel-devops or something like that
destroy_env 'before'
sudo ${my_dir}/provision_fuel.sh "MirantisOpenStack-${fuel_version}.iso" ${fuel_nodes}

${my_dir}/$inner_script

save_logs
destroy_env 'after'
trap - ERR
