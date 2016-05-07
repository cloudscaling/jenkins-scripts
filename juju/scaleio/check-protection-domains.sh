#!/bin/bash -e

USERNAME=admin
PASSWORD=Default_password

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

source $my_dir/../functions

cd juju-scaleio

m1=$(juju add-machine --constraints "instance-type=i2.2xlarge" 2>&1 | awk '{print $3}')
echo "Machine created: $m1"
m2=$(juju add-machine --constraints "instance-type=i2.2xlarge" 2>&1 | awk '{print $3}')
echo "Machine created: $m2"

wait_for_machines $m1 $m2

echo "---------------------------------------------------------------------------"
echo "------------------------------------------------------------ Deploy MDM ---"
echo "---------------------------------------------------------------------------"
juju deploy local:trusty/scaleio-mdm --to 0

echo "---------------------------------------------------------------------------"
echo "----------------- Deploy SDS 1 (pd1; fs1; sp1,sp2; /dev/xvdb,/dev/xvdc) ---"
echo "---------------------------------------------------------------------------"
juju deploy local:trusty/scaleio-sds scaleio-sds-pd1 --to $m1
juju set scaleio-sds-pd1 protection-domain="pd1" fault-set="fs1" storage-pools="sp1,sp2" device-paths="/dev/xvdb,/dev/xvdc"
juju add-relation scaleio-sds-pd1 scaleio-mdm

echo "---------------------------------------------------------------------------"
echo "----------------- Deploy SDS 2 (pd1; fs1; sp2,sp1; /dev/xvdb,/dev/xvdc) ---"
echo "---------------------------------------------------------------------------"
juju deploy local:trusty/scaleio-sds scaleio-sds-pd2 --to $m2
juju set scaleio-sds-pd2 protection-domain="pd2" fault-set="fs2" storage-pools="sp2,sp1" device-paths="/dev/xvdb,/dev/xvdc"
juju add-relation scaleio-sds-pd2 scaleio-mdm

# wait
wait_for_services "executing|blocked|waiting|allocating"

# check for errors
if juju status | grep "current" | grep error ; then
  echo "ERROR: Some services went to error state"
  juju ssh 0 sudo grep Error /var/log/juju/all-machines.log 2>/dev/null
  exit 1
fi

#TODO: Check sds protection-domains, fault-sets, storage-pools, device-paths

if ! `juju ssh 0 "scli --login --username $USERNAME --password $PASSWORD --approve_certificate >/dev/null ; scli --query_all_sds" 2>/dev/null >/tmp/all_sds` ; then
  echo 'ERROR: The command "scli --query_all_sds --approve_certificate" failed'
  echo "$output"
  exit 1
fi

#Check if all SDS are connected
echo "---------------------------------------------------------------------------"
echo "------------------------------------------------------------- Check SDS ---"
echo "---------------------------------------------------------------------------"
if cat /tmp/all_sds | grep "SDS ID" | grep -v "State: Connected" ; then
  echo 'ERROR: Not all sds are connected'
  echo "$output"
  exit 1
else
  echo 'All sds are connected'
fi

sds[1]=$(cat /tmp/all_sds | grep "scaleio_sds_pd1" | awk '{print $3}')
sds[2]=$(cat /tmp/all_sds | grep "scaleio_sds_pd2" | awk '{print $3}')

for i in 1 2 ; do
  echo "---------------------------------------------------------------------------"
  echo "-------------------------------------- Check SDS in protection domain $i ---"
  echo "---------------------------------------------------------------------------"
  juju ssh 0 "scli --login --username $USERNAME --password $PASSWORD --approve_certificate >/dev/null ; scli --query_sds --sds_id ${sds[$i]} " 2>/dev/null >/tmp/sds_pd$i
  if [[ `cat /tmp/sds_pd$i | grep 'Protection Domain:' | awk '{print $5}'` != pd$i* ]] ; then
    echo "Error in protection domain in scaleio_sds_pd$i"
    cat /tmp/sds_pd$i
    exit 1
  fi
  if [[ `cat /tmp/sds_pd$i | grep "Fault Set:" | awk '{print $5}'` != fs$i* ]] ; then
    echo "Error in fault set in scaleio_sds_pd$i"
    cat /tmp/sds_pd$i
    exit 1
  fi
  if [[ -z `cat /tmp/sds_pd$i | grep "Device information" | grep "total 2 devices"` ]] ; then
    echo "Error in devices number in scaleio_sds_pd$i"
    cat /tmp/sds_pd$i
    exit 1
  fi
  if [[ $i == 1 ]] ; then
    other=2
  else
    other=1
  fi
  if [[ -z `cat /tmp/sds_pd$i | grep "Path: /dev/xvdb"` ]] ; then
    echo "Error in device path in scaleio_sds_pd$i"
    cat /tmp/sds_pd$i
    exit 1
  fi
  if [[ -z `cat /tmp/sds_pd$i | sed -n '/Path: \/dev\/xvdb/{n;p}' | grep "Storage Pool: sp$i"` ]] ; then
    echo "Error in storage pool in scaleio_sds_pd$i"
    cat /tmp/sds_pd$i
    exit 1
  fi
  if [[ -z `cat /tmp/sds_pd$i | grep "Path: /dev/xvdc"` ]] ; then
    echo "Error in device path in scaleio_sds_pd$i"
    cat /tmp/sds_pd$i
    exit 1
  fi
  if [[ -z `cat /tmp/sds_pd$i | sed -n '/Path: \/dev\/xvdc/{n;p}' | grep "Storage Pool: sp$other"` ]] ; then
    echo "Error in storage pool in scaleio_sds_pd$i"
    cat /tmp/sds_pd$i
    exit 1
  fi
done

juju status

echo SUCCESS
