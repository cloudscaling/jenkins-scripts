#!/bin/bash -e

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"
my_name="$(basename "$0")"

source $my_dir/../functions

m1="$1"
m2="$2"
m3="$3"
if [[ -z "$m1" || -z "$m2" || -z "$m3" ]] ; then
  echo "ERROR: script takes machine1, machine2 and machine3 as parameters"
  exit 1
fi

cd juju-scaleio

trap 'catch_errors $LINENO' ERR EXIT
function catch_errors() {
  local exit_code=$?
  echo "Line: $1  Error=$exit_code  Command: '$BASH_COMMAND'"

  juju remove-service scaleio-sds || /bin/true
  juju remove-service scaleio-mdm || /bin/true
  wait_for_removed "scaleio-sds" || /bin/true
  wait_for_removed "scaleio-mdm" || /bin/true
  exit $exit_code
}

ret=0

echo "INFO: Deploy MDM to 0"
juju deploy local:trusty/scaleio-mdm --to 0

echo "INFO: Deploy SDS with disabled RMCache and RFCache"
juju deploy local:trusty/scaleio-sds --to $m1
juju add-unit scaleio-sds --to $m2
juju add-unit scaleio-sds --to $m3
juju set scaleio-sds protection-domain='pd' storage-pools='sp' device-paths='/dev/xvdf' rmcache-usage=dont_use rfcache-usage=dont_use
juju add-relation scaleio-sds scaleio-mdm
wait_status


function check_cache() {
  local param_name=$1
  local param_value=$2

  if ! output=`juju ssh 0 "scli --login --username $USERNAME --password $PASSWORD --approve_certificate >/dev/null ; scli --query_storage_pool --protection_domain_name pd --storage_pool_name sp" 2>/dev/null` ; then
    echo "ERROR: ($my_name:$LINENO) Login and command 'scli --query_storage_pool --protection_domain_name pd --storage_pool_name sp' failed"
    echo "$output"
    return 1
  fi

  if ! echo "$output" | grep "$param_name" | grep -q "$param_value" ; then
    echo "ERROR: ($my_name:$LINENO) Parameter '$param_name' is not in state '$param_value'"
    echo "$output" | grep "$param_name"
    (( ++ret ))
  else
    echo "INFO: Success. Parameter '$param_name' is in state '$param_value'"
  fi
}

echo "INFO: Check RMCache"
check_cache 'RAM Read Cache' "Doesn't use"
echo "INFO: Check RFCache"
check_cache 'Flash Read Cache' "Doesn't use"

echo "INFO: Enable RMCache"
juju set scaleio-sds rmcache-usage=use
wait_status
echo "INFO: Check RMCache"
check_cache 'RAM Read Cache' "Uses"
check_cache 'RAM Read Cache write handling mode' "cached"

echo "INFO: Set caching write-mode to passthrough"
juju set scaleio-sds rmcache-write-handling-mode=passthrough
wait_status
echo "INFO: Check RMCache write-mode"
check_cache 'RAM Read Cache write handling mode' "passthrough"

echo "INFO: Set caching write-mode to cached"
juju set scaleio-sds rmcache-write-handling-mode=cached
wait_status
echo "INFO: Check RMCache write-mode"
check_cache 'RAM Read Cache write handling mode' "cached"

rfcache_path='/dev/xvdg'
echo "INFO: Enable RFCache"
juju set scaleio-sds rfcache-usage=use rfcache-device-paths=$rfcache_path
wait_status
echo "INFO: Check RFCache"
check_cache 'Flash Read Cache' "Uses"

echo "INFO: Check RFCache path"
if ! output=`juju ssh 0 "scli --login --username $USERNAME --password $PASSWORD >/dev/null ; scli --query_all_sds" 2>/dev/null` ; then
  echo "ERROR: ($my_name:$LINENO) Login and command 'scli --query_all_sds' failed"
  echo "$output"
  exit 1
fi

sds_names=`echo "$output" | grep 'SDS ID:' | awk '{print$5}'`
for sds_name in $sds_names ; do
  rfcache_device=`juju ssh 0 "scli --login --username $USERNAME --password $PASSWORD >/dev/null ; scli --query_sds --sds_name $sds_name | sed -n '/Rfcache device information/{n;p;}'" 2>/dev/null`
  if ! echo "$rfcache_device" | awk '{print$5}' | grep -q "$rfcache_path" ; then
    echo "ERROR: ($my_name:$LINENO) Path of RfCache device on $sds_name isn't $rfcache_path"
    echo "$rfcache_device"
    (( ++ret ))
  else
    echo "INFO: Success. Path of RFCache device on $sds_name is $rfcache_path."
  fi
done

juju remove-service scaleio-sds
juju remove-service scaleio-mdm
wait_for_removed "scaleio-sds"
wait_for_removed "scaleio-mdm"

trap - ERR EXIT
exit $ret
