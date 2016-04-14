#!/bin/bash -ex

git clone https://github.com/openstack/ec2-api.git
cd ec2-api
source ~/devstack/accrc/admin/admin
unset OS_AUTH_TYPE

function die() {
  echo "ERROR in $1: $2"
  exit 1
}
export -f die
function warn() {
  echo "WARNING in $1: $2"
}
export -f warn

openstack endpoint list --os-identity-api-version=3
openstack service list --long
if [[ "$?" -ne "0" ]]; then
  echo "Looks like credentials are absent."
  exit 1
fi

STACK_USER=$(whoami) EC2API_DIR="." devstack/create_config functional_tests.conf

cat functional_tests.conf >> /opt/stack/tempest/etc/tempest.conf
