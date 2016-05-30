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
juju set scaleio-sds-pd1 zero-padding-policy=enable protection-domain="pd1" fault-set="fs1" storage-pools="sp1,sp2" device-paths="/dev/xvdb,/dev/xvdc"
juju add-relation scaleio-sds-pd1 scaleio-mdm

echo "---------------------------------------------------------------------------"
echo "----------------- Deploy SDS 2 (pd1; fs1; sp2,sp1; /dev/xvdb,/dev/xvdc) ---"
echo "---------------------------------------------------------------------------"
juju deploy local:trusty/scaleio-sds scaleio-sds-pd2 --to $m2
juju set scaleio-sds-pd2 protection-domain="pd2" fault-set="fs2" storage-pools="sp2,sp1" device-paths="/dev/xvdb,/dev/xvdc"
juju add-relation scaleio-sds-pd2 scaleio-mdm

wait_status

if ! output=`juju ssh 0 "scli --login --username $USERNAME --password $PASSWORD --approve_certificate >/dev/null ; scli --query_all_sds" 2>/dev/null` ; then
  echo "ERROR: The command scli --login --username $USERNAME --password $PASSWORD --approve_certificate >/dev/null ; scli --query_all_sds --approve_certificate 2>/dev/null failed"
  echo "$output"
  exit 1
fi

#Check if all SDS are connected
echo "---------------------------------------------------------------------------"
echo "------------------------------------------------------------- Check SDS ---"
echo "---------------------------------------------------------------------------"
if [[ `echo "$output" | grep "SDS ID" | grep "State: Connected" | wc -l` != 2 ]] ; then
  echo 'ERROR: Not all sds are connected'
  echo "$output"
  exit 1
fi

sds[1]=$(echo "$output" | grep "scaleio_sds_pd1" | awk '{print $3}')
sds[2]=$(echo "$output" | grep "scaleio_sds_pd2" | awk '{print $3}')

for i in 1 2 ; do
  echo "---------------------------------------------------------------------------"
  echo "-------------------------------------- Check SDS in protection domain $i ---"
  echo "---------------------------------------------------------------------------"
  if ! sds_output=`juju ssh 0 "scli --login --username $USERNAME --password $PASSWORD --approve_certificate >/dev/null ; scli --query_sds --sds_id ${sds[$i]} " 2>/dev/null` ; then
    echo "ERROR: The command scli --login --username $USERNAME --password $PASSWORD --approve_certificate ; scli --query_sds --sds_id ${sds[$i]} "
    echo "$sds_output"
    exit 1
  fi
  if [[ `echo "$sds_output" | grep 'Protection Domain:' | awk '{print $5}'` != pd$i* ]] ; then
    echo "Error in protection domain in scaleio_sds_pd$i"
    echo "$sds_output"
    exit 1
  fi
  if [[ `echo "$sds_output" | grep "Fault Set:" | awk '{print $5}'` != fs$i* ]] ; then
    echo "Error in fault set in scaleio_sds_pd$i"
    echo "$sds_output"
    exit 1
  fi
  if ! echo "$sds_output" | grep "Device information" | grep "total 2 devices" >/dev/null ; then
    echo "Error in devices number in scaleio_sds_pd$i"
    echo "$sds_output"
    exit 1
  fi
  if ! echo "$sds_output" | grep "Path: /dev/xvdb" >/dev/null ; then
    echo "Error in device path in scaleio_sds_pd$i"
    echo "$sds_output"
    exit 1
  fi
  if ! echo "$sds_output" | sed -n '/Path: \/dev\/xvdb/{n;p}' | grep "Storage Pool: sp$i" >/dev/null ; then
    echo "Error in storage pool $i in scaleio_sds_pd$i"
    echo "$sds_output"
    exit 1
  fi
  if ! echo "$sds_output" | grep "Path: /dev/xvdc" >/dev/null ; then
    echo "Error in device path in scaleio_sds_pd$i"
    echo "$sds_output"
    exit 1
  fi
  if ! echo "$sds_output" | sed -n '/Path: \/dev\/xvdc/{n;p}' | grep "Storage Pool: sp$((3-i))" >/dev/null ; then
    echo "Error in storage pool $((3-i)) in scaleio_sds_pd$i"
    echo "$sds_output"
    exit 1
  fi
done

echo "--------------------------------------------------- Query storage pools ---"
juju ssh 0 "scli --login --username $USERNAME --password $PASSWORD --approve_certificate >/dev/null ; scli --query_storage_pool --protection_domain_name pd1 --storage_pool_name sp1" 2>/dev/null
juju ssh 0 "scli --login --username $USERNAME --password $PASSWORD --approve_certificate >/dev/null ; scli --query_storage_pool --protection_domain_name pd1 --storage_pool_name sp2" 2>/dev/null
juju ssh 0 "scli --login --username $USERNAME --password $PASSWORD --approve_certificate >/dev/null ; scli --query_storage_pool --protection_domain_name pd2 --storage_pool_name sp1" 2>/dev/null
juju ssh 0 "scli --login --username $USERNAME --password $PASSWORD --approve_certificate >/dev/null ; scli --query_storage_pool --protection_domain_name pd2 --storage_pool_name sp2" 2>/dev/null

echo SUCCESS
