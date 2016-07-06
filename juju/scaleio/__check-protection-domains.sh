#!/bin/bash -e

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"
my_name="$(basename "$0")"

source $my_dir/../functions

m1="$1"
m2="$2"
if [[ -z "$m1" || -z "$m2" ]] ; then
  echo "ERROR: ($my_name:$LINENO) script takes machine1 and machine2 as parameters"
  exit 1
fi

trap 'catch_errors $LINENO' ERR EXIT
function catch_errors() {
  local exit_code=$?
  echo "Line: $1  Error=$exit_code  Command: '$BASH_COMMAND'"

  juju remove-service scaleio-mdm || /bin/true
  juju remove-service scaleio-sds-pd1 || /bin/true
  juju remove-service scaleio-sds-pd2 || /bin/true
  wait_for_removed "scaleio-mdm" || /bin/true
  trap - ERR EXIT
  exit $exit_code
}

echo "INFO: Deploy MDM"
juju deploy --repository juju-scaleio local:scaleio-mdm --to 0

echo "INFO: Deploy SDS 1 (pd1; fs1; sp1,sp2; /dev/xvdf,/dev/xvdg)"
juju deploy --repository juju-scaleio local:scaleio-sds scaleio-sds-pd1 --to $m1
juju set scaleio-sds-pd1 zero-padding-policy=enable protection-domain="pd1" fault-set="fs1" storage-pools="sp1,sp2" device-paths="/dev/xvdf,/dev/xvdg"
juju add-relation scaleio-sds-pd1 scaleio-mdm

echo "INFO: Deploy SDS 2 (pd1; fs1; sp2,sp1; /dev/xvdf,/dev/xvdg)"
juju deploy --repository juju-scaleio local:scaleio-sds scaleio-sds-pd2 --to $m2
juju set scaleio-sds-pd2 protection-domain="pd2" fault-set="fs2" storage-pools="sp2,sp1" device-paths="/dev/xvdf,/dev/xvdg"
juju add-relation scaleio-sds-pd2 scaleio-mdm

wait_status

ret=0

if ! output=`juju ssh 0 "scli --login --username $USERNAME --password $PASSWORD --approve_certificate >/dev/null && scli --query_all_sds" 2>/dev/null` ; then
  echo "ERROR: ($my_name:$LINENO) The command scli --login --username $USERNAME --password $PASSWORD --approve_certificate >/dev/null && scli --query_all_sds --approve_certificate 2>/dev/null failed"
  echo "$output"
  exit 1
fi

#Check if all SDS are connected
echo "INFO: Check SDS"
if [[ `echo "$output" | grep "SDS ID" | grep "State: Connected" | wc -l` != 2 ]] ; then
  ret=2
  echo 'ERROR: ($my_name:$LINENO) Not all sds are connected'
  echo "$output"
fi

sds[1]=$(echo "$output" | grep "scaleio_sds_pd1" | awk '{print $3}')
sds[2]=$(echo "$output" | grep "scaleio_sds_pd2" | awk '{print $3}')

for i in 1 2 ; do
  echo "INFO: Check SDS in protection domain $i"
  if ! sds_output=`juju ssh 0 "scli --login --username $USERNAME --password $PASSWORD >/dev/null && scli --query_sds --sds_id ${sds[$i]} " 2>/dev/null` ; then
    (( ++ret ))
    echo "ERROR: ($my_name:$LINENO) The command scli --login --username $USERNAME --password $PASSWORD --approve_certificate && scli --query_sds --sds_id ${sds[$i]} "
    echo "$sds_output"
    continue
  fi
  if [[ `echo "$sds_output" | grep 'Protection Domain:' | awk '{print $5}'` != pd$i* ]] ; then
    (( ++ret ))
    echo "ERROR: ($my_name:$LINENO) Error in protection domain in scaleio_sds_pd$i"
    echo "$sds_output"
  fi
  if [[ `echo "$sds_output" | grep "Fault Set:" | awk '{print $5}'` != fs$i* ]] ; then
    (( ++ret ))
    echo "ERROR: ($my_name:$LINENO) Error in fault set in scaleio_sds_pd$i"
    echo "$sds_output"
  fi
  if ! echo "$sds_output" | grep "Device information" | grep -q "total 2 devices" ; then
    (( ++ret ))
    echo "ERROR: ($my_name:$LINENO) Error in devices number in scaleio_sds_pd$i"
    echo "$sds_output"
  fi
  if ! echo "$sds_output" | grep "Path: /dev/xvdf" >/dev/null ; then
    (( ++ret ))
    echo "ERROR: ($my_name:$LINENO) Error in device path in scaleio_sds_pd$i"
    echo "$sds_output"
  fi
  if ! echo "$sds_output" | sed -n '/Path: \/dev\/xvdf/{n;p}' | grep -q "Storage Pool: sp$i" ; then
    (( ++ret ))
    echo "ERROR: ($my_name:$LINENO) Error in storage pool $i in scaleio_sds_pd$i"
    echo "$sds_output"
  fi
  if ! echo "$sds_output" | grep -q "Path: /dev/xvdg" ; then
    (( ++ret ))
    echo "ERROR: ($my_name:$LINENO) Error in device path in scaleio_sds_pd$i"
    echo "$sds_output"
  fi
  if ! echo "$sds_output" | sed -n '/Path: \/dev\/xvdg/{n;p}' | grep -q "Storage Pool: sp$((3-i))" ; then
    (( ++ret ))
    echo "ERROR: ($my_name:$LINENO) Error in storage pool $((3-i)) in scaleio_sds_pd$i"
    echo "$sds_output"
  fi
done

if [[ $ret == 0 ]] ; then
  echo "INFO: Check successed"
fi

juju remove-service scaleio-mdm
juju remove-service scaleio-sds-pd1
juju remove-service scaleio-sds-pd2
wait_for_removed "scaleio-mdm"

trap - ERR EXIT
exit $ret

