#!/bin/bash -e

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

source $my_dir/../functions

cd juju-scaleio

function catch_errors() {
  local exit_code=$?
  juju remove-service scaleio-sds || /bin/true
  juju remove-service scaleio-mdm || /bin/true
  wait_for_removed "scaleio-sds" || /bin/true
  wait_for_removed "scaleio-mdm" || /bin/true
  exit $exit_code
}

function check_cache {
  if ! output=`juju ssh 0 "scli --login --username $USERNAME --password $PASSWORD --approve_certificate >/dev/null ; scli --query_storage_pool --protection_domain_name pd --storage_pool_name sp" 2>/dev/null` ; then
    echo "ERROR: (${BASH_SOURCE[0]}:$LINENO) Login and command 'scli --query_storage_pool --protection_domain_name pd --storage_pool_name sp' failed"
    echo "$output"
    return 1
  fi

  if ! echo "$output" | grep "$1" | grep -q "$2" ; then
    echo "ERROR: (${BASH_SOURCE[0]}:$LINENO) Parameter $1 is in wrong state"
    echo "$output" | grep "$1"
    (( ++ret ))
  else
    echo "INFO: Success. Parameter $1 is in state $2."
  fi
}

m1="$1"
m2="$2"
m3="$3"
if [[ -z "$m1" && -z "$m2" && -z "$m3" ]] ; then
  echo "ERROR: script takes machine1, machine2 and machine3 as parameters"
  exit 1
fi

echo "INFO: Deploy MDM to 0"
juju deploy local:trusty/scaleio-mdm --to 0

echo "INFO: Deploy SDS with disabled RMCache and RFCache"
juju deploy local:trusty/scaleio-sds --to $m1
juju add-unit scaleio-sds --to $m2
juju add-unit scaleio-sds --to $m3
juju set scaleio-sds protection-domain='pd' storage-pools='sp' device-paths='/dev/xvdf' rmcache-usage=dont_use rfcache-usage=dont_use
juju add-relation scaleio-sds scaleio-mdm
wait_status

trap catch_errors ERR EXIT

ret=0

echo "INFO: Check RMCache"
check_cache 'RAM Read Cache' "Doesn't use"
echo "INFO: Check RFCache"
check_cache 'RAM Read Cache' "Doesn't use"

echo "INFO: Enable RMCache"
juju set scaleio-sds rmcache-usage=use
sleep 5
wait_status

echo "INFO: Check RMCache"
check_cache 'RAM Read Cache' "Uses"
check_cache 'RAM Read Cache write handling mode' "cached"

echo "INFO: Change caching write-mode to passthrough"
juju set scaleio-sds rmcache-write-handling-mode=passthrough
sleep 5
wait_status

echo "INFO: Check RMCache write-mode"
check_cache 'RAM Read Cache write handling mode' "passthrough"

echo "INFO: Change caching write-mode to cached"
juju set scaleio-sds rmcache-write-handling-mode=cached
sleep 5
wait_status

echo "INFO: Check RMCache write-mode"
check_cache 'RAM Read Cache write handling mode' "cached"

echo "INFO: Enable RFCache"
juju set scaleio-sds rfcache-usage=use rfcache-device-paths=/dev/xvdg
sleep 5
wait_status

echo "INFO: Check RFCache"
check_cache 'Flash Read Cache' "Uses"

juju remove-service scaleio-sds
juju remove-service scaleio-mdm
wait_for_removed "scaleio-sds"
wait_for_removed "scaleio-mdm"

trap - ERR EXIT
exit $ret
