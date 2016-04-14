#!/bin/bash -e

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

if ! juju bootstrap ; then
  echo "Bootstrap error. exiting..."
  exit 1
fi

trap catch_errors ERR

function save_logs() {
  # save status to file
  rm -rf logs
  mkdir logs
  juju status > logs/juju_status.log
  juju ssh 0 sudo cat /var/log/juju/all-machines.log > logs/all-machines.log 2>/dev/null
}

function catch_errors() {
  local exit_code=$?
  echo "Errors!" $exit_code $@

  save_logs

  if [[ $CLEAN_ENV != 'false' ]] ; then
    juju destroy-environment -y amazon
  fi

  exit $exit_code
}

$my_dir/scaleio/check-mdm-cluster.sh

save_logs

if [[ $CLEAN_ENV != 'false' ]] ; then
  juju destroy-environment -y amazon
fi
