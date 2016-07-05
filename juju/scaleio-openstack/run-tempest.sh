#!/bin/bash -e

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

source $my_dir/../functions
source $my_dir/../functions-openstack

auth_ip=`juju status keystone --format tabular | awk '/keystone\/0/{print $7}'`
keystone_machine=`juju status keystone --format tabular | awk '/keystone\/0/{print $5}'`
juju scp $my_dir/__setup_cloud_accounts.sh $keystone_machine: 2>/dev/null
juju ssh $keystone_machine "auth_ip=$auth_ip bash -e __setup_cloud_accounts.sh" 2>/dev/null

export OS_AUTH_URL=http://$auth_ip:5000/v2.0
export OS_USERNAME=admin
export OS_TENANT_NAME=admin
export OS_PROJECT_NAME=admin
export OS_PASSWORD=password

create_virtualenv
image_id=`create_image`
image_id_alt=`create_image cirros_alt`
create_flavors
create_network

cd $WORKSPACE/tempest

cp $my_dir/accounts.yaml $(pwd)/etc/
CONF="$(pwd)/etc/tempest.conf"
cp $my_dir/tempest.conf $CONF
sed -i "s/%AUTH_IP%/$auth_ip/g" $CONF
sed -i "s|%TEMPEST_DIR%|$(pwd)|g" $CONF
sed -i "s/%IMAGE_ID%/$image_id/g" $CONF
sed -i "s/%IMAGE_ID_ALT%/$image_id_alt/g" $CONF

tox -eall-plugin -- --concurrency 1 "(tempest\.api\.compute|tempest\.api\.image|tempest\.api\.volume)"

testr last --subunit | subunit-1to2 | python $WORKSPACE/jenkins-scripts/tempest/subunit2jenkins.py -o test_result.xml -s scaleio-openstack

cd $my_dir
