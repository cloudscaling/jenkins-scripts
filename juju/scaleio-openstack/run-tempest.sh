#!/bin/bash -e

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

source $my_dir/../functions
source $my_dir/../functions-openstack

VERSION=${VERSION:-"cloud:trusty-liberty"}
VERSION=${VERSION#*-}

auth_ip=`get_machine_ip keystone`
keystone_machine=`get_machine keystone`
juju scp $my_dir/tempest/__setup_cloud_accounts.sh $keystone_machine: 2>/dev/null
juju ssh $keystone_machine "auth_ip=$auth_ip bash -e __setup_cloud_accounts.sh" 2>/dev/null

nova_api_machine=`get_machine nova-cloud-controller`
filters=`juju ssh $nova_api_machine "sudo grep scheduler_default_filters /etc/nova/nova.conf | cut -d '=' -f 2" 2>/dev/null`

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
rm -f *.xml

cp $my_dir/tempest/accounts.yaml $(pwd)/etc/
CONF="$(pwd)/etc/tempest.conf"
cp $my_dir/tempest/tempest.conf $CONF
sed -i "s/%AUTH_IP%/$auth_ip/g" $CONF
sed -i "s|%TEMPEST_DIR%|$(pwd)|g" $CONF
sed -i "s/%IMAGE_ID%/$image_id/g" $CONF
sed -i "s/%IMAGE_ID_ALT%/$image_id_alt/g" $CONF
sed -i "s/%SCHEDULER_FILTERS%/$filters/g" $CONF

source $WORKSPACE/.venv/bin/activate
pip install -r requirements.txt
pip install junitxml

tests=$(mktemp)
tests_regex="(tempest\.api\.compute|tempest\.api\.image|tempest\.api\.volume)"
python -m testtools.run discover -t ./ ./tempest/test_discover --list | grep -P "$tests_regex" > $tests
tests_filtered=$(mktemp)
python $my_dir/tempest/format_test_list.py $my_dir/tempest excludes.$VERSION $tests > $tests_filtered

export OS_TEST_TIMEOUT=700
[ -d .testrepository ] || testr init

set +e
#python -m subunit.run discover -t ./ ./tempest/test_discover --load-list=$tests_filtered | subunit-trace -n -f
testr run --subunit --parallel --concurrency=2 --load-list=$tests_filtered | subunit-trace -n -f
exit_code=$?

testr last --subunit | subunit-1to2 | python $WORKSPACE/jenkins-scripts/tempest/subunit2jenkins.py -o test_result.xml -s scaleio-openstack

deactivate

cd $my_dir

rm -f $tests $tests_filtered

exit $exit_code
