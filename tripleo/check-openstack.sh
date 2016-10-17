#!/bin/bash -e

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

sudo yum install -y wget gcc python-devel
sudo easy_install pip
sudo pip install virtualenv

source $my_dir/../juju/functions
source $my_dir/../juju/functions-openstack

. ~/stackrc
master_mdm=`nova list | grep controller-0 | awk '{print $12}' | cut -d '=' -f 2`

. ~/overcloudrc
# create network with same name as in fuel - run_os_checks will check this name
if ! neutron net-list | grep net04 ; then
  neutron net-create net04
  neutron subnet-create --gateway 10.1.0.1 net04 10.1.0.0/24
fi

function exec_on_mdm() {
  ssh heat-admin@$master_mdm "$@"
}

function get_provisioning_type() {
  # TODO: get real value from overcloud settings
  echo 'thin'
}

echo "INFO: Master MDM found at $master_mdm"

create_virtualenv
run_os_checks exec_on_mdm get_provisioning_type
