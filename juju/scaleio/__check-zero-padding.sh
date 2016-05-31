#!/bin/bash -e

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

source $my_dir/../functions

cd juju-scaleio

trap catch_errors ERR
function catch_errors() {
  local exit_code=$?
  juju remove-service scaleio-sds-zp || /bin/true
  juju remove-service scaleio-sds || /bin/true
  juju remove-service scaleio-mdm || /bin/true
  wait_for_removed "scaleio-sds-zp" || /bin/true
  wait_for_removed "scaleio-sds" || /bin/true
  wait_for_removed "scaleio-mdm" || /bin/true
  exit $exit_code
}

m1="$1"
m2="$2"
if [[ -z "$m1" && -z "$m2" ]] ; then
  echo "ERROR: script takes machine1 and machine2 as parameters"
  exit 1
fi

echo "INFO: Deploy MDM to 0"
juju deploy local:trusty/scaleio-mdm --to 0
wait_status

echo "INFO: Deploy SDS with disabled zero-padding to m1"
juju deploy local:trusty/scaleio-sds --to $m1
juju set scaleio-sds protection-domain="pd" fault-set="fs1" storage-pools="sp1" device-paths="/dev/xvdb" zero-padding-policy="disable"
juju add-relation scaleio-sds scaleio-mdm

echo "INFO: Deploy SDS with enabled zero-padding to m2"
juju deploy local:trusty/scaleio-sds scaleio-sds-zp --to $m2
juju set scaleio-sds-zp protection-domain="pd" fault-set="fs2" storage-pools="sp2" device-paths="/dev/xvdb" zero-padding-policy="enable"
juju add-relation scaleio-sds-zp scaleio-mdm
wait_status


zero_padding_sp1=`juju ssh 0 "scli --login --username $USERNAME --password $PASSWORD --approve_certificate >/dev/null ; scli --query_storage_pool --protection_domain_name pd --storage_pool_name sp1 | grep 'Zero padding'" 2>/dev/null | awk '{print$4}' | sed "s/\r//"`
zero_padding_sp2=`juju ssh 0 "scli --login --username $USERNAME --password $PASSWORD >/dev/null ; scli --query_storage_pool --protection_domain_name pd --storage_pool_name sp2 | grep 'Zero padding'" 2>/dev/null | awk '{print$4}' | sed "s/\r//"`

echo "INFO: Check zero-padding policy"
if [[ "$zero_padding_sp1" != "disabled" ]] ; then
  echo "ERROR: Zero-padding policy on SDS1 is expected disabled, but got $zero_padding_sp1"
fi
if [[ "$zero_padding_sp2" != "enabled" ]] ; then
  echo "ERROR: Zero-padding policy on SDS2 is expected enabled, but got $zero_padding_sp2"
fi

juju remove-service scaleio-sds-zp
juju remove-service scaleio-sds
juju remove-service scaleio-mdm
wait_for_removed "scaleio-sds-zp"
wait_for_removed "scaleio-sds"
wait_for_removed "scaleio-mdm"

cd ..
