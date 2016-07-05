#!/bin/bash -e

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

auth_ip=`juju status keystone --format tabular | awk '/keystone\/0/{print $7}'`
keystone_machine=`juju status keystone --format tabular | awk '/keystone\/0/{print $5}'`
juju scp $my_dir/__setup_cloud_accounts.sh $keystone_machine: 2>/dev/null
juju ssh $keystone_machine "auth_ip=$auth_ip bash -e __setup_cloud_accounts.sh" 2>/dev/null

export OS_AUTH_URL=http://$auth_ip:5000/v2.0
export OS_USERNAME=admin
export OS_TENANT_NAME=admin
export OS_PROJECT_NAME=admin
export OS_PASSWORD=password

# check installed cloud
rm -rf .venv
virtualenv .venv
source .venv/bin/activate
pip install -q python-openstackclient

if ! openstack image show cirros &>/dev/null ; then
  rm -f cirros-0.3.4-x86_64-disk.img
  wget -t 2 -T 60 -nv http://download.cirros-cloud.net/0.3.4/cirros-0.3.4-x86_64-disk.img
  openstack image create --public --file cirros-0.3.4-x86_64-disk.img cirros
fi
image_id=`openstack image show cirros | awk '/ id /{print $4}'`

if ! nova flavor-show 51 &>/dev/null ; then
  nova flavor-create fl8gb 51 512 8 1
fi
if ! nova flavor-show 52 &>/dev/null ; then
  nova flavor-create fl16gb 52 512 16 1
fi

deactivate

cd $WORKSPACE/tempest

cp $my_dir/accounts.yaml $(pwd)/etc/
CONF="$(pwd)/etc/tempest.conf"
cp $my_dir/tempest.conf $CONF
sed -i "s/%AUTH_IP%/$auth_ip/g" $CONF
sed -i "s|%TEMPEST_DIR%|$(pwd)|g" $CONF
sed -i "s/%IMAGE_ID%/$image_id/g" $CONF

tox -eall-plugin "(tempest\.api\.compute|tempest\.api\.image|tempest\.api\.volume)"

cd $my_dir
