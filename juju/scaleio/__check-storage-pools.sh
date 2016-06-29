#!/bin/bash -e

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"
my_name="$(basename "$0")"

source $my_dir/../functions

m1="$1"
m2="$2"
m3="$3"
if [[ -z "$m1" || -z "$m2" || -z "$m3" ]] ; then
  echo "ERROR: ($my_name:$LINENO) script takes three machines as parameters"
  exit 1
fi

function remove_services() {
  juju remove-service scaleio-mdm || /bin/true
  juju remove-service scaleio-sds1 || /bin/true
  juju remove-service scaleio-sds2 || /bin/true
  juju remove-service scaleio-sds3 || /bin/true
  wait_for_removed "scaleio-mdm" || /bin/true
  wait_for_removed "scaleio-sds1" || /bin/true
  wait_for_removed "scaleio-sds2" || /bin/true
  wait_for_removed "scaleio-sds3" || /bin/true
}

trap 'catch_errors $LINENO' ERR EXIT
function catch_errors() {
  local exit_code=$?
  echo "Line: $1  Error=$exit_code  Command: '$BASH_COMMAND'"

  trap - ERR EXIT
  remove_services
  exit $exit_code
}

echo "INFO: Deploy MDM"
juju deploy --repository juju-scaleio local:trusty/scaleio-mdm --to 0

machines[1]=$m1
machines[2]=$m2
machines[3]=$m3
for (( i=1; i<4; ++i )) ; do
  echo "INFO: Deploy SDS $i (sp1,sp1,sp2; /dev/xvdf,/dev/xvdg,/dev/xvdh)"
  sds="scaleio-sds$i"
  juju deploy --repository juju-scaleio local:trusty/scaleio-sds $sds --to ${machines[$i]}
  juju set $sds storage-pools="sp1,sp1,sp2" protection-domain=pd device-paths="/dev/xvdf,/dev/xvdg,/dev/xvdh"
  juju add-relation $sds scaleio-mdm
done

wait_status

ret=0

if ! output=`juju ssh 0 "scli --login --username $USERNAME --password $PASSWORD --approve_certificate >/dev/null && scli --query_all_sds" 2>/dev/null` ; then
  echo "ERROR: ($my_name:$LINENO) The command scli --login --username $USERNAME --password $PASSWORD --approve_certificate >/dev/null && scli --query_all_sds --approve_certificate 2>/dev/null failed"
  echo "$output"
  exit 1
fi

#Check if all SDS are connected
echo "INFO: Check SDS"
if [[ `echo "$output" | grep "SDS ID" | grep "State: Connected" | wc -l` != 3 ]] ; then
  ret=2
  echo 'ERROR: ($my_name:$LINENO) Not all sds are connected'
  echo "$output"
fi


echo "INFO: check volume creation"
juju ssh 0 "scli --login --username $USERNAME --password $PASSWORD >/dev/null && scli --add_volume --size_gb 16 --storage_pool_name sp1 --protection_domain_name pd" 2>/dev/null || (( ++ret ))
juju ssh 0 "scli --login --username $USERNAME --password $PASSWORD >/dev/null && scli --add_volume --size_gb 8 --storage_pool_name sp2 --protection_domain_name pd" 2>/dev/null || (( ++ret ))
sleep 5

if ! output=`juju ssh 0 "scli --login --username $USERNAME --password $PASSWORD >/dev/null && scli --query_all_volumes" 2>/dev/null` ; then
  (( ++ret ))
  echo "ERROR: ($my_name:$LINENO) The command scli --login --username $USERNAME --password $PASSWORD --approve_certificate && scli --query_all_volumes"
  echo "$output"
  continue
fi

for i in 1 2 ; do
  if ! echo "$output" | grep -A 1 sp$i | grep "Volume ID" ; then
    (( ++ret ))
    echo "ERROR: ($my_name:$LINENO) Volume in sp$i is absent"
    echo "$output"
  fi
done

if [[ $ret == 0 ]] ; then
  echo "INFO: Check successed"
fi

trap - ERR EXIT
remove_services
exit $ret

