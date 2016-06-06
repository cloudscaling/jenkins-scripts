#!/bin/bash -e

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

source $my_dir/../functions

cd juju-scaleio

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

function check_storage_pool {
  local sp=$3
  if ! output=`juju ssh 0 "scli --login --username $USERNAME --password $PASSWORD --approve_certificate >/dev/null ; scli --query_storage_pool --protection_domain_name pd --storage_pool_name $sp" 2>/dev/null` ; then
    echo "ERROR: (${BASH_SOURCE[0]}:$LINENO) Login and command 'scli --query_storage_pool --protection_domain_name pd --storage_pool_name $sp' failed"
    echo "$output"
    return 1
  fi

  if echo "$output" | grep "$1" | grep -q -v "$2" ; then
    echo "ERROR: (${BASH_SOURCE[0]}:$LINENO) Parameter $1 is in wrong state"
    echo "$output" | grep "$1"
    return 2
  fi
  echo "INFO: Success. Parameter $1 is $2."
}

m1="$1"
m2="$2"
if [[ -z "$m1" && -z "$m2" ]] ; then
  echo "ERROR: script takes machine1 and machine2 as parameters"
  exit 1
fi

echo "INFO: Deploy MDM to 0"
juju deploy local:trusty/scaleio-mdm --to 0

echo "INFO: Deploy SDS with disabled zero-padding to 1"
juju deploy local:trusty/scaleio-sds --to $m1
juju set scaleio-sds protection-domain='pd' fault-set='fs1' storage-pools='sp1' device-paths='/dev/xvdb' zero-padding-policy='disable' checksum-mode='disable' scanner-mode='disable' spare-percentage='10'
juju add-relation scaleio-sds scaleio-mdm

echo "INFO: Deploy SDS with enabled zero-padding to 2"
juju deploy local:trusty/scaleio-sds scaleio-sds-zp --to $m2
juju set scaleio-sds-zp protection-domain='pd' fault-set='fs2' storage-pools='sp2' device-paths='/dev/xvdb' zero-padding-policy='enable'
juju add-relation scaleio-sds-zp scaleio-mdm
trap catch_errors ERR EXIT
wait_status

ret=0

# Zero padding test
echo 'INFO: Check zero-padding policy on SP1'
if ! check_storage_pool 'Zero padding' 'disabled' 'sp1' ; then
  ret=1
fi
echo 'INFO: Check zero-padding policy on SP2'
if ! check_storage_pool 'Zero padding' 'enabled' 'sp2' ; then
  ret=2
fi

echo 'INFO: Try to change zero-padding'
juju set scaleio-sds zero-padding-policy='enable'

wait_absence_status_for_services "executing|blocked|waiting|allocating"

echo "INFO: Check for errors"
if juju status | grep "current" | grep error >/dev/null ; then
  error_status='Status: This operation is only allowed when there are no devices in the Storage Pool.'
  error_output=`juju ssh 0 sudo grep Error /var/log/juju/all-machines.log 2>/dev/null`
  if [[ "$error_output" != *"$error_status"* ]] ; then
    ret=3
    echo "ERROR: Unexpected error has occurred"
    echo $error_output
  else
    echo "INFO: Expected behavior. $error_status"
    mdm_unit=`juju status | grep "scaleio-mdm/" | sed "s/[:\r]//"`
    echo "INFO: Resolve"
    juju resolved $mdm_unit
    wait_status
    juju set scaleio-sds zero-padding-policy='disable'
    wait_status
  fi
else
  ret=4
  echo "ERROR: Unexpected behavior."
fi

# Checksum mode test
echo 'INFO: Check checksum mode (disabled)'
if ! check_storage_pool 'Checksum mode' 'disabled' 'sp1' ; then
  ret=5
fi

echo 'INFO: Change checksum mode'
juju set scaleio-sds checksum-mode='enable'
sleep 5
wait_status
echo 'INFO: Check checksum mode (enabled)'
if ! check_storage_pool 'Checksum mode' 'enabled' 'sp1' ; then
  ret=6
fi

# Scanner mode
echo 'INFO: Check scanner mode (disabled)'
if ! check_storage_pool 'Background device scanner' 'Disabled' 'sp1' ; then
  ret=7
fi

echo 'INFO: Change scanner mode'
juju set scaleio-sds scanner-mode='enable'
sleep 5
wait_status
echo 'INFO: Check scanner mode (enabled)'
if ! check_storage_pool 'Background device scanner' 'Mode: device_only' 'sp1' ; then
  ret=8
fi

# Spare percentage
echo 'INFO: Check spare percentage (10%)'
if ! check_storage_pool 'Spare policy' '10%' 'sp1' ; then
  ret=9
fi

echo 'INFO: Change spare percentage'
juju set scaleio-sds spare-percentage='15'
sleep 5
wait_status
echo 'INFO: Check spare percentage (15%)'
if ! check_storage_pool 'Spare policy' '15%' 'sp1' ; then
  ret=10
fi

juju remove-service scaleio-sds-zp
juju remove-service scaleio-sds
juju remove-service scaleio-mdm
wait_for_removed "scaleio-sds-zp"
wait_for_removed "scaleio-sds"
wait_for_removed "scaleio-mdm"

trap - ERR EXIT
exit $ret
