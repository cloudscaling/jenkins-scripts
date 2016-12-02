#!/bin/bash -e

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"
my_name="$(basename "$0")"

source $my_dir/../functions

m1="$1"
m2="$2"
if [[ -z "$m1" || -z "$m2" ]] ; then
  echo "ERROR: script takes machine1 and machine2 as parameters"
  exit 1
fi

trap 'catch_errors $LINENO' ERR EXIT
function catch_errors() {
  local exit_code=$?
  echo "Line: $1  Error=$exit_code  Command: '$(eval echo $BASH_COMMAND)'"
  trap - ERR EXIT

  juju-remove-service scaleio-sds-zp || /bin/true
  juju-remove-service scaleio-sds || /bin/true
  juju-remove-service scaleio-mdm || /bin/true
  wait_for_removed "scaleio-sds-zp" || /bin/true
  wait_for_removed "scaleio-sds" || /bin/true
  wait_for_removed "scaleio-mdm" || /bin/true

  exit $exit_code
}

ret=0

echo "INFO: Deploy MDM to 0"
juju-deploy --repository juju-scaleio local:scaleio-mdm --to 0

echo "INFO: Deploy SDS with disabled zero-padding to $m1"
juju-deploy --repository juju-scaleio local:scaleio-sds --to $m1
juju-set scaleio-sds protection-domain='pd' fault-set='fs1' storage-pools='sp1' device-paths='/dev/xvdf' zero-padding-policy='disable' checksum-mode='disable' scanner-mode='disable' spare-percentage='10'
juju-add-relation scaleio-sds scaleio-mdm

echo "INFO: Deploy SDS with enabled zero-padding to $m2"
juju-deploy --repository juju-scaleio local:scaleio-sds scaleio-sds-zp --to $m2
juju-set scaleio-sds-zp protection-domain='pd' fault-set='fs2' storage-pools='sp2' device-paths='/dev/xvdf' zero-padding-policy='enable'
juju-add-relation scaleio-sds-zp scaleio-mdm
wait_status


function check_storage_pool {
  local param_name=$1
  local param_value=$2
  local sp=$3
  if ! output=`juju-ssh 0 "scli --login --username $USERNAME --password $PASSWORD --approve_certificate >/dev/null && scli --query_storage_pool --protection_domain_name pd --storage_pool_name $sp" 2>/dev/null` ; then
    echo "ERROR: ($my_name:$LINENO) Login and command 'scli --query_storage_pool --protection_domain_name pd --storage_pool_name $sp' failed"
    echo "$output"
    return 1
  fi

  if ! echo "$output" | grep "$param_name" | grep -q "$param_value" ; then
    echo "ERROR: ($my_name:$LINENO) Parameter '$param_name' is not in state '$param_value'"
    echo "$output" | grep "$param_name"
    (( ++ret ))
  else
    echo "INFO: Success. Parameter $param_name is '$param_value'"
  fi
}

# Zero padding test
echo 'INFO: Check zero-padding policy on SP1'
check_storage_pool 'Zero padding' 'disabled' 'sp1'
echo 'INFO: Check zero-padding policy on SP2'
check_storage_pool 'Zero padding' 'enabled' 'sp2'

echo 'INFO: Try to change zero-padding'
juju-set scaleio-sds zero-padding-policy='enable'

wait_absence_status_for_services "executing|blocked|waiting|allocating"

echo "INFO: Check for errors"
if juju-status | grep "current" | grep -q error ; then
  mdm_unit=`juju-status | grep "scaleio-mdm/" | sed "s/[:\r]//" | sed -e 's/^[[:space:]]*//'`
  mdm_unit_log_name="unit-${mdm_unit//\//-}"
  echo "INFO: Checking file /var/log/juju/$mdm_unit_log_name on machine 0"
  log_items=`juju-ssh 0 "sudo cat /var/log/juju/$mdm_unit_log_name" 2>/dev/null`
  error_status='Error: MDM failed command.  Status: This operation is only allowed when there are no devices in the Storage Pool. Please remove all devices from the Storage Pool.'
  if ! echo "$log_items" | grep -q "$error_status" ; then
    (( ++ret ))
    echo "ERROR: Unexpected error has occurred. Please check logs after test. Current date: $(date)"
  else
    echo "INFO: Expected error"
    juju-set scaleio-sds zero-padding-policy='disable'
  fi

  echo "INFO: Resolve error and continue checking"
  juju-resolved $mdm_unit
  wait_status
else
  (( ++ret ))
  echo "ERROR: Error expected but all services are ok."
fi

# Checksum mode test
echo 'INFO: Check checksum mode (disabled)'
check_storage_pool 'Checksum mode' 'disabled' 'sp1'

echo 'INFO: Set checksum mode to "enable"'
juju-set scaleio-sds checksum-mode='enable'
wait_status
echo 'INFO: Check checksum mode (enabled)'
check_storage_pool 'Checksum mode' 'enabled' 'sp1'

# Scanner mode
echo 'INFO: Check scanner mode (disabled)'
check_storage_pool 'Background device scanner' 'Disabled' 'sp1'

echo 'INFO: Set scanner mode to "enable"'
juju-set scaleio-sds scanner-mode='enable'
wait_status
echo 'INFO: Check scanner mode (enabled)'
check_storage_pool 'Background device scanner' 'Mode: device_only' 'sp1'

# Spare percentage
echo 'INFO: Check spare percentage (10%)'
check_storage_pool 'Spare policy' '10%' 'sp1'

echo 'INFO: Set spare percentage to 15'
juju-set scaleio-sds spare-percentage='15'
wait_status
echo 'INFO: Check spare percentage (15%)'
check_storage_pool 'Spare policy' '15%' 'sp1'

juju-remove-service scaleio-sds-zp
juju-remove-service scaleio-sds
juju-remove-service scaleio-mdm
wait_for_removed "scaleio-sds-zp"
wait_for_removed "scaleio-sds"
wait_for_removed "scaleio-mdm"

trap - ERR EXIT
exit $ret

