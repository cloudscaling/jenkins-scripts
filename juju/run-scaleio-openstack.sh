#!/bin/bash -e

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

source $my_dir/functions

USERNAME="admin"
PASSWORD="Default_password"

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

master_mdm=`get_master_mdm`
cluster_mode=$(juju get scaleio-mdm | grep -A 4 scaleio-mdm | grep "value:" | awk '{print $2}')

$my_dir/scaleio/check-cluster.sh "juju ssh" $master_mdm $cluster_mode
$my_dir/scaleio/check-sds.sh "juju ssh" $master_mdm $USERNAME $PASSWORD '/dev/xvdb'
$my_dir/scaleio/check-sdc.sh "juju ssh" $master_mdm $USERNAME $PASSWORD

$my_dir/scaleio-openstack/check-openstack.sh

$my_dir/scaleio-openstack/save_logs.sh

if [[ $CLEAN_ENV != 'false' ]] ; then
  juju destroy-environment -y amazon
fi
