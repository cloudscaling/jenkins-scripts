#!/bin/bash -e

inner_script=${1:-}
if [ -z "$inner_script" ] ; then
  echo "No script is specified but required"
  exit 1
fi

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

log_dir=$WORKSPACE/logs
rm -rf $log_dir
mkdir $log_dir

source $my_dir/functions

SERIES=${SERIES:-trusty}
export SERIES

if ! juju-bootstrap ; then
  echo "Bootstrap error. exiting..."
  exit 1
fi
AZ=`juju-status | grep -Po " availability-zone=.*[ $]*" | cut -d '=' -f 2`
echo "INFO: Availability zone of this deployment is $AZ"
export AZ

trap 'catch_errors $LINENO' ERR

function save_logs() {
  $my_dir/save_logs.sh
}

function catch_errors() {
  local exit_code=$?
  echo "Line: $1  Error=$exit_code  Command: '$(eval echo $BASH_COMMAND)'"
  trap - ERR

  # sleep some time to flush logs
  sleep 20
  save_logs

  if [[ $CLEAN_ENV != 'false' ]] ; then
    cleanup_environment
  fi

  exit $exit_code
}

rm -rf logs
mkdir logs

$my_dir/$inner_script

save_logs

if [[ $CLEAN_ENV != 'false' ]] ; then
  cleanup_environment
fi

trap - ERR
