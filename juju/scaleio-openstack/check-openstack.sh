#!/bin/bash -e

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

rm -f errors
touch errors
export MAX_FAIL=30

source $my_dir/../functions
source $my_dir/../functions-openstack

master_mdm=`get_master_mdm`
echo "Master MDM found at $master_mdm"

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
wait_volume $volume_id $MAX_FAIL

echo "------------------------------  Check cinder volumes"
echo "------------------------------  Check volume from image"
cinder create --image-id $image_id --display_name volume_from_image 1
volume_id=`cinder list | grep " volume_from_image " | awk '{print $2}'`
wait_volume $volume_id $MAX_FAIL

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
wait_instance $instance_id $MAX_FAIL
nova show $iname
echo "------------------------------  Console log"
nova console-log $iname | tail -10
echo "------------------------------  Check live migration"
nova live-migration $iname
sleep 20
wait_instance $instance_id $MAX_FAIL
nova show $iname
host2=`nova show $iname | grep "$host_attr" | awk '{print $4}'`
if [[ "$host1" == "$host2" ]] ; then
  echo '' >> errors
  echo "ERROR: Host is not changed after live migration." >> errors
fi

echo "------------------------------  Run instance from ephemeral"
iname="instance_01"
nova boot --flavor 51 --image cirros $iname
instance_id=`nova list | grep " $iname " | awk '{print $2}'`
wait_instance $instance_id $MAX_FAIL
nova show $iname
host_attr='OS-EXT-SRV-ATTR:host'
host1=`nova show $iname | grep "$host_attr" | awk '{print $4}'`
echo "------------------------------  Console log"
nova console-log $iname | tail
echo "------------------------------  Check live migration"
nova live-migration $iname
sleep 20
wait_instance $instance_id $MAX_FAIL
nova show $iname
host2=`nova show $iname | grep "$host_attr" | awk '{print $4}'`
if [[ "$host1" == "$host2" ]] ; then
  echo '' >> errors
  echo "ERROR: Host is not changed after live migration." >> errors
fi

echo "------------------------------  Check flavor with additional Ephemeral and swap "
iname="instance_02"
nova boot --flavor 53 --image cirros $iname
instance_id=`nova list | grep " $iname " | awk '{print $2}'`
wait_instance $instance_id $((2*MAX_FAIL))
nova show $iname

# check existing volumes type
current_type=`juju get scaleio-openstack | grep -A 15 provisioning-type | grep "value:" | head -1 | awk '{print $2}'`
echo "------------------------------ Check that all volumes in ScaleIO has type: $current_type"
volumes=`juju ssh $master_mdm "scli --login --username admin --password Default_password --approve_certificate && scli --query_all_volume" 2>/dev/null | grep 'Volume ID:'`
vcount=`echo "$volumes" | wc -l`
vtcount=`echo "$volumes" | grep -i "$current_type\-provisioned" | wc -l`
if [[ $vcount != $vtcount ]] ; then
  echo "------------------------------ ERROR: Some volume has another type"
  echo '' >> errors
  echo "ERROR: Some volumes has different type" >> errors
  echo "$volumes" >> errors
else
  echo "------------------------------ All volumes in ScaleIO has type: $current_type"
fi

# remove OpenStack objects
cinder delete simple_volume || /bin/true
nova delete inst_from_volume || /bin/true
nova delete instance_01 || /bin/true
nova delete instance_02 || /bin/true

# check snapshots
echo "------------------------------  Creating volume"
cinder create --display_name volume_for_snaps 1
volume_id=`cinder list | grep " volume_for_snaps " | awk '{print $2}'`
wait_volume $volume_id $MAX_FAIL

echo "------------------------------  Creating snapshot"
cinder snapshot-create volume_for_snaps
snapshot_id=`cinder snapshot-list | grep $volume_id | awk '{print$2}'`
wait_snapshot $snapshot_id $MAX_FAIL

echo "------------------------------  Creating volume from snapshot"
cinder create --snapshot_id $snapshot_id --name from_snapshot
snap_volume_id=`cinder list | grep " from_snapshot " | awk '{print $2}'`
wait_volume $snap_volume_id $MAX_FAIL

cinder delete $snap_volume_id
echo "------------------------------ Deleting snapshot"
cinder snapshot-delete $snapshot_id
sleep 5
if `cinder snapshot-list | grep $snapshot_id ` ; then
  echo '' >> errors
  echo "Snapshot $snapshot_id wasn't deleted." >> errors
fi
cinder delete $volume_id

echo "------------------------------  Creating instance"
iname="instance_for_snaps"
nova boot --flavor 51 --image cirros $iname
instance_id=`nova list | grep " $iname " | awk '{print $2}'`
wait_instance $instance_id $MAX_FAIL

echo "------------------------------  Creating snapshot"
nova image-create $instance_id snapshot_image
snapshot_id=`openstack image show snapshot_image | grep " id " | awk '{print $4}'`
wait_image $snapshot_id $MAX_FAIL

echo "------------------------------  Creating instance from snapshot"
iname="from_snapshot"
simage_id=`openstack image show from_snapshot | grep " id " | awk '{print $4}'`
nova boot --flavor 51 --image $simage_id $iname
instance_id=`nova list | grep " $iname " | awk '{print $2}'`
wait_instance $instance_id $((2*MAX_FAIL))

echo "------------------------------  Deleting snapshot"
openstack image delete $simage_id
sleep 5
if `openstack image list | grep $simage_id ` ; then
  echo '' >> errors
  echo "Snapshot wasn't deleted." >> errors
fi
nova delete instance_for_snaps
nova delete from_snapshot


# all checks is done and we cant switch off traps
set +e

# here we try to list all infos from ScaleIO
if [ -n $master_mdm ] ; then
  set -x
  juju ssh $master_mdm "scli --login --username admin --password Default_password --approve_certificate && scli --query_all_volume" 2>/dev/null
  juju ssh $master_mdm "scli --login --username admin --password Default_password --approve_certificate && scli --query_all_sds" 2>/dev/null
  juju ssh $master_mdm "scli --login --username admin --password Default_password --approve_certificate && scli --query_all_sdc" 2>/dev/null
  juju ssh $master_mdm "scli --login --username admin --password Default_password --approve_certificate && scli --query_performance_parameters --all_sds --all_sdc" 2>/dev/null
  nova list
  cinder list
  set +x
fi


if [ -s errors ] ; then
  cat errors
  exit 1
fi
