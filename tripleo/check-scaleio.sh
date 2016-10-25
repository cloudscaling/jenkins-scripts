#!/bin/bash -e

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

sudo yum install -y wget gcc python-devel
sudo easy_install pip
sudo pip install virtualenv

source $my_dir/../juju/functions
source $my_dir/../juju/functions-openstack
source $my_dir/../juju/scaleio/static-checks

. /home/stack/stackrc
master_mdm=`nova list | grep controller-0 | awk '{print $12}' | cut -d '=' -f 2`
ssh_to_mdm_opts="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"
function exec_on_mdm() {
  ssh $ssh_to_mdm_opts heat-admin@$master_mdm "$@"
}
function get_provisioning_type() {
  # TODO: get real value from overcloud settings
  echo 'thin'
}
echo "INFO: Master MDM found at $master_mdm"


# basic checks
# TODO: change cluster mode/user/password to real values
cluster_mode='3'
USERNAME="admin"
PASSWORD="Default_password"

errors=0
check-cluster "ssh $ssh_to_mdm_opts" heat-admin@$master_mdm $cluster_mode || ((++errors))
check-sds "ssh $ssh_to_mdm_opts" heat-admin@$master_mdm $USERNAME $PASSWORD '/dev/vdb' || ((++errors))
check-sdc "ssh $ssh_to_mdm_opts" heat-admin@$master_mdm $USERNAME $PASSWORD || ((++errors))
check-performance "ssh $ssh_to_mdm_opts" heat-admin@$master_mdm $USERNAME $PASSWORD || ((++errors))

if (( errors > 0 )) ; then
  echo "ERROR: basic checks errors ($errors) !"
  #exit $errors
fi

# openstack checks
. /home/stack/overcloudrc
# create network with same name as in fuel - run_os_checks will check this name
if ! neutron net-list | grep net04 ; then
  neutron net-create net04
  neutron subnet-create --gateway 10.1.0.1 net04 10.1.0.0/24
fi

create_virtualenv
run_os_checks exec_on_mdm get_provisioning_type

if (( errors > 0 )) ; then
  exit $errors
fi
