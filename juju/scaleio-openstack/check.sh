#!/bin/bash -e

rm -f errors
touch errors
MAX_FAIL=30

function volume_status() { cinder show $1 | awk '/ status / {print $4}'; }
instance_status() { nova show $1 | awk '/ status / {print $4}'; }

function wait_volume() {
  local volume_id=$1
  echo "------------------------------  Wait for volume: $volume_id"
  local fail=0
  while [[ true ]] ; do
    if ((fail >= MAX_FAIL)); then
      echo '' >> errors
      echo "ERROR: Volume creation fails (timeout)" >> errors
      cinder show $volume_id >> errors
      return
    fi
    echo "attempt $fail of $MAX_FAIL"
    status=$(volume_status $volume_id)
    if [[ $status == "available" ]]; then
      break
    fi
    if [[ $status == "error" || -z "$status" ]]; then
      echo '' >> errors
      echo 'ERROR: Volume creation error' >> errors
      cinder show $volume_id >> errors
      return
    fi
    sleep 10
    ((++fail))
  done
}

function wait_instance() {
  local instance_id=$1
  echo "------------------------------  Wait for instance: $instance_id"
  local fail=0
  while [[ true ]] ; do
    if ((fail >= MAX_FAIL)); then
      echo '' >> errors
      echo "ERROR: Instance active status wait timeout occured" >> errors
      nova show $instance_id >> errors
      return 0
    fi
    echo "attempt $fail of $MAX_FAIL"
    status=$(instance_status $instance_id)
    if [[ "$status" == "ACTIVE" ]]; then
      break
    fi
    if [[ "$status" == "ERROR" || -z "$status" ]]; then
      echo '' >> errors
      echo 'ERROR: Instance booting error' >> errors
      nova show $instance_id >> errors
      return 0
    fi
    sleep 10
    ((++fail))
  done
}

# check installed cloud
auth_ip=`juju status keystone/0 --format json | jq .services.keystone.units | grep public-address | sed 's/[\",]//g' | awk '{print $2}'`
rm -rf .venv
virtualenv .venv
source .venv/bin/activate
pip install -q python-openstackclient

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
nova boot --flavor 1 --block-device "device=/dev/vda,id=$volume_id,shutdown=remove,source=volume,dest=volume,bootindex=0" inst_from_volume
instance_id=`nova list | grep " inst_from_volume " | awk '{print $2}'`
wait_instance $instance_id
nova show inst_from_volume
echo "------------------------------  Console log"
nova console-log inst_from_volume | tail -10

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

# here we try to list volumes in ScaleIO
master_mdm=''
for mch in `juju status scaleio-mdm --format json | jq .machines | jq keys | tail -n +2 | head -n -1 | sed -e "s/[\",]//g"` ; do
  echo "Machine: $mch"
  juju ssh $mch sudo scli --query_cluster --approve_certificate 2>/dev/null
  if [[ $? == 0 ]] ; then
    master_mdm=$mch
  fi
done
echo "Master MDM found at $master_mdm"
if [ -n $master_mdm ] ; then
  juju ssh $master_mdm "scli --login --username admin --password Default_password --approve_certificate ; scli --query_all_volume --approve_certificate" 2>/dev/null
  juju ssh $master_mdm "scli --login --username admin --password Default_password --approve_certificate ; scli --query_all_sds --approve_certificate" 2>/dev/null
  juju ssh $master_mdm "scli --login --username admin --password Default_password --approve_certificate ; scli --query_all_sdc --approve_certificate" 2>/dev/null
  juju ssh $master_mdm "scli --login --username admin --password Default_password --approve_certificate ; scli --query_performance_parameters --all_sds --all_sdc" 2>/dev/null
fi


if [ -s errors ] ; then
  cat errors
  exit 1
fi
