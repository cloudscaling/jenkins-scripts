#!/bin/bash -e

inner_script="${1:-deploy.sh}"
shift
script_params="$@"

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
AZ=`juju status | grep -Po " availability-zone=.*[ $]*" | cut -d '=' -f 2`
echo "INFO: Availability zone of this deployment is $AZ"
export AZ

trap 'catch_errors $LINENO' ERR EXIT

function catch_errors() {
  local exit_code=$?
  echo "Line: $1  Error=$exit_code  Command: '$(eval echo $BASH_COMMAND)'"
  trap - ERR EXIT

  $my_dir/scaleio-openstack/save_logs.sh

  if [[ $CLEAN_ENV != 'false' ]] ; then
    juju destroy-environment -y amazon
  fi

  exit $exit_code
}

echo "--------------------------------------------- Run deploy script: $inner_script"
$my_dir/scaleio-openstack/$inner_script $script_params

master_mdm=`get_master_mdm`
cluster_mode=`get_config scaleio-mdm cluster-mode`
errors=0
check-cluster "juju ssh" $master_mdm $cluster_mode || ((++errors))
check-sds "juju ssh" $master_mdm $USERNAME $PASSWORD '/dev/xvdf' || ((++errors))
check-sdc "juju ssh" $master_mdm $USERNAME $PASSWORD || ((++errors))
check-performance "juju ssh" $master_mdm $USERNAME $PASSWORD || ((++errors))

if (( errors > 0 )) ; then
  exit $errors
fi

$my_dir/scaleio-openstack/check-openstack.sh

if [[ "$RUN_TEMPEST" == 'true' ]] ; then
  $my_dir/scaleio-openstack/run-tempest.sh
fi

$my_dir/scaleio-openstack/save_logs.sh

if [[ $CLEAN_ENV != 'false' ]] ; then
  juju destroy-environment -y amazon
fi

trap - ERR EXIT
