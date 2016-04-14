#!/bin/bash -e
my_dir="$(dirname "$0")"

#aws ec2 delete-security-group --group-name juju-amazon || /bin/true

if ! juju bootstrap ; then
  echo "Bootstrap error. exiting..."
  exit 1
fi

trap catch_errors ERR

function catch_errors() {
  local exit_code=$?
  echo "Errors!" $exit_code $@

  $my_dir/scaleio-openstack/save_logs.sh

  if [[ $CLEAN_ENV != 'false' ]] ; then
    juju destroy-environment -y amazon
  fi

  exit $exit_code
}

$my_dir/scaleio-openstack/deploy.sh

$my_dir/scaleio-openstack/check.sh

$my_dir/scaleio-openstack/save_logs.sh

if [[ $CLEAN_ENV != 'false' ]] ; then
  juju destroy-environment -y amazon
fi
