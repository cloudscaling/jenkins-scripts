#!/bin/bash -e

inner_script="${1:-deploy.sh}"

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

source $my_dir/functions
source $my_dir/scaleio/static-checks

USERNAME="admin"
PASSWORD="Default_password"

if ! juju bootstrap ; then
  echo "Bootstrap error. exiting..."
  exit 1
fi

trap 'catch_errors $LINENO' ERR EXIT

function catch_errors() {
  local exit_code=$?
  echo "Line: $1  Error=$exit_code  Command: '$BASH_COMMAND'"

  $my_dir/scaleio-openstack/save_logs.sh

  if [[ $CLEAN_ENV != 'false' ]] ; then
    juju destroy-environment -y amazon
  fi

  trap - ERR EXIT
  exit $exit_code
}

echo "--------------------------------------------- Run deploy script: $inner_script"
$my_dir/scaleio-openstack/$inner_script

master_mdm=`get_master_mdm`
cluster_mode=`get_cluster_mode`
errors=0
check-cluster "juju ssh" $master_mdm $cluster_mode || ((++errors))
check-sds "juju ssh" $master_mdm $USERNAME $PASSWORD '/dev/xvdf' || ((++errors))
check-sdc "juju ssh" $master_mdm $USERNAME $PASSWORD || ((++errors))
check-performance "juju ssh" $master_mdm $USERNAME $PASSWORD || ((++errors))

if (( errors > 0 )) ; then
  exit $errors
fi

$my_dir/scaleio-openstack/check-openstack.sh

$my_dir/scaleio-openstack/save_logs.sh

if [[ $CLEAN_ENV != 'false' ]] ; then
  juju destroy-environment -y amazon
fi

trap - ERR EXIT
