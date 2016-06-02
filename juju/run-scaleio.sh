#!/bin/bash -e

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

inner_script=${1:-}
if [ -z "$inner_script" ] ; then
  echo "No script is specified but required"
  exit 1
fi

if ! juju bootstrap ; then
  echo "Bootstrap error. exiting..."
  exit 1
fi

trap 'catch_errors $LINENO' ERR

function save_logs() {
  # save status to file
  juju status > logs/juju_status.log
  juju ssh 0 sudo cat /var/log/juju/all-machines.log > logs/all-machines.log 2>/dev/null
}

function catch_errors() {
  local exit_code=$?
  echo "Line: $1  Error=$exit_code  Command: '$BASH_COMMAND'"

  # sleep some time to flush logs
  sleep 20
  save_logs

  if [[ $CLEAN_ENV != 'false' ]] ; then
    juju destroy-environment -y amazon
  fi

  exit $exit_code
}

rm -rf logs
mkdir logs

$my_dir/$inner_script

save_logs

if [[ $CLEAN_ENV != 'false' ]] ; then
  juju destroy-environment -y amazon
fi

trap - ERR
