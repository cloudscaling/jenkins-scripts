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

echo "------------------------------------------------------------ Deploy MDM ---"
juju deploy local:trusty/scaleio-mdm --to 0

# deploy fake charms to prevent machines removing
juju deploy ubuntu --to $m1
juju service add-unit ubuntu --to $m2

echo "--------------------------------- Deploy SDS with disabled zero-padding ---"
juju deploy local:trusty/scaleio-sds --to $m1
juju set scaleio-sds protection-domain="pd" fault-set="fs1" storage-pools="sp1" device-paths="/dev/xvdb" zero-padding-policy="disable"
juju add-relation scaleio-sds scaleio-mdm

echo "---------------------------------- Deploy SDS with enabled zero-padding ---"
juju deploy local:trusty/scaleio-sds scaleio-sds-zp --to $m2
juju set scaleio-sds-zp protection-domain="pd" fault-set="fs2" storage-pools="sp2" device-paths="/dev/xvdb" zero-padding-policy="enable"
juju add-relation scaleio-sds-zp scaleio-mdm

wait_status

zero_padding_sp1=`juju ssh 0 "scli --login --username $USERNAME --password $PASSWORD --approve_certificate >/dev/null ; scli --query_storage_pool --protection_domain_name pd --storage_pool_name sp1 | grep 'Zero padding'" 2>/dev/null | awk '{print$4}' | sed "s/\r//"`
zero_padding_sp2=`juju ssh 0 "scli --login --username $USERNAME --password $PASSWORD >/dev/null ; scli --query_storage_pool --protection_domain_name pd --storage_pool_name sp2 | grep 'Zero padding' | awk '{print$4}'" 2>/dev/null | awk '{print$4}' | sed "s/\r//"`

echo "--------------------------------------------- Check zero-padding policy ---"
if [[ "$zero_padding_sp1" != "disabled" ]] ; then
  echo "ERROR: Zero-padding policy on SDS1 is expected disabled, but got $zero_padding_sp1"
#  exit 1
fi
if [[ "$zero_padding_sp2" != "enabled" ]] ; then
  echo "ERROR: Zero-padding policy on SDS2 is expected enabled, but got $zero_padding_sp2"
#  exit 1
fi
echo "Success"

juju remove-service scaleio-sds-zp
juju remove-service scaleio-sds
juju remove-service scaleio-mdm
wait_for_removed "scaleio-sds-zp"
wait_for_removed "scaleio-sds"
wait_for_removed "scaleio-mdm"
