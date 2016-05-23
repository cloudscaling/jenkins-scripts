#!/bin/bash -e

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

rm -f errors
touch errors
export MAX_FAIL=30

source $my_dir/../functions
source $my_dir/functions

# check installed cloud
rm -rf .venv
virtualenv .venv
source .venv/bin/activate
pip install -q python-openstackclient

auth_ip=`juju status keystone/0 --format json | jq .services.keystone.units | grep public-address | sed 's/[\",]//g' | awk '{print $2}'`
export OS_AUTH_URL=http://$auth_ip:5000/v2.0
export OS_USERNAME=admin
export OS_TENANT_NAME=admin
export OS_PROJECT_NAME=admin
export OS_PASSWORD=password

keystone catalog
rm -f cirros-0.3.4-x86_64-disk.img
wget -nv http://download.cirros-cloud.net/0.3.4/cirros-0.3.4-x86_64-disk.img
openstack image create --public --file cirros-0.3.4-x86_64-disk.img cirros
image_id=`openstack image show cirros | grep " id " | awk '{print $4}'`


echo "------------------------------  Check cinder volumes"
echo "------------------------------  Check simple volume"
cinder create --display_name simple_volume 1
volume_id=`cinder list | grep " simple_volume " | awk '{print $2}'`
wait_volume $volume_id

echo "------------------------------  Check cinder volumes"
echo "------------------------------  Check volume forom image"
cinder create --image-id $image_id --display_name volume_from_image 1
volume_id=`cinder list | grep " volume_from_image " | awk '{print $2}'`
wait_volume $volume_id

cinder list


echo "------------------------------  Add specific flavors"
nova flavor-create fl8gb 51 512 8 1
nova flavor-create fl16gb 52 512 16 1
nova flavor-create fl8gbext --ephemeral 8 --swap 8192 53 512 8 1
sleep 2

echo "------------------------------  Run instance from bootable volume"
iname='inst_from_volume'
nova boot --flavor 1 --block-device "device=/dev/vda,id=$volume_id,shutdown=remove,source=volume,dest=volume,bootindex=0" $iname
instance_id=`nova list | grep " $iname " | awk '{print $2}'`
wait_instance $instance_id
nova show $iname
echo "------------------------------  Console log"
nova console-log $iname | tail -10
echo "------------------------------  Check live migration"
nova live-migration $iname
sleep 20
wait_instance $instance_id
nova show $iname
host2=`nova show $iname | grep "$host_attr" | awk '{print $4}'`
if [[ "$host1" == "$host2" ]] ; then
  echo '' >> errors
  echo "\n""ERROR: Host is not changed after live migration." >> errors
fi

echo "------------------------------  Run instance from ephemeral"
iname="instance_01"
nova boot --flavor 51 --image cirros $iname
instance_id=`nova list | grep " $iname " | awk '{print $2}'`
wait_instance $instance_id
nova show $iname
host_attr='OS-EXT-SRV-ATTR:host'
host1=`nova show $iname | grep "$host_attr" | awk '{print $4}'`
echo "------------------------------  Console log"
nova console-log $iname | tail
echo "------------------------------  Check live migration"
nova live-migration $iname
sleep 20
wait_instance $instance_id
nova show $iname
host2=`nova show $iname | grep "$host_attr" | awk '{print $4}'`
if [[ "$host1" == "$host2" ]] ; then
  echo '' >> errors
  echo "\n""ERROR: Host is not changed after live migration." >> errors
fi

echo "------------------------------  Check flavor with Ephemeral and swap "
iname="instance_02"
nova boot --flavor 53 --image cirros $iname
instance_id=`nova list | grep " $iname " | awk '{print $2}'`
wait_instance $instance_id
nova show $iname


# all checks is done and we cant switch off traps
set +e

# here we try to list all infos from ScaleIO
master_mdm=`get_master_mdm`
echo "Master MDM found at $master_mdm"
if [ -n $master_mdm ] ; then
  set -x
  juju ssh $master_mdm "scli --login --username admin --password Default_password --approve_certificate ; scli --query_all_volume --approve_certificate" 2>/dev/null
  juju ssh $master_mdm "scli --login --username admin --password Default_password --approve_certificate ; scli --query_all_sds --approve_certificate" 2>/dev/null
  juju ssh $master_mdm "scli --login --username admin --password Default_password --approve_certificate ; scli --query_all_sdc --approve_certificate" 2>/dev/null
  juju ssh $master_mdm "scli --login --username admin --password Default_password --approve_certificate ; scli --query_performance_parameters --all_sds --all_sdc" 2>/dev/null
  set +x
fi


if [ -s errors ] ; then
  cat errors
  exit 1
fi
