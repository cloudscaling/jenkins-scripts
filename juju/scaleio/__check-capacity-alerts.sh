#!/bin/bash -e

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

source $my_dir/../functions

cd juju-scaleio

trap catch_errors ERR EXIT
function catch_errors() {
  local exit_code=$?
  juju remove-service scaleio-mdm || /bin/true
  wait_for_removed "scaleio-mdm" || /bin/true
  exit $exit_code
}

echo "INFO: Deploy MDM to 0"
juju deploy local:trusty/scaleio-mdm --to 0
wait_status

echo "INFO: Check capacity alert thresholds"
query_all=`juju ssh 0 "scli --login --username $USERNAME --password $PASSWORD --approve_certificate >/dev/null && scli --query_all" 2>/dev/null`
current_capacity_threshold_high=`echo "$query_all" | grep 'Capacity alert thresholds' | awk '{print$5}'`
current_capacity_threshold_critical=`echo "$query_all" | grep 'Capacity alert thresholds' | awk '{print$7}'`
echo "INFO: Current capacity thresholds are $current_capacity_threshold_high and $current_capacity_threshold_critical"

new_capacity_threshold_high=79
new_capacity_threshold_critical=89

echo "INFO: change capacity alert thresholds"
juju set scaleio-mdm capacity-high-alert-threshold="$new_capacity_threshold_high" capacity-critical-alert-threshold="$new_capacity_threshold_critical"
wait_status

echo "INFO: check new capacity alert thresholds"
query_all=`juju ssh 0 "scli --login --username $USERNAME --password $PASSWORD >/dev/null && scli --query_all" 2>/dev/null`
current_capacity_threshold_high=`echo "$query_all" | grep 'Capacity alert thresholds' | awk '{print$5}' | sed "s/,//"`
current_capacity_threshold_critical=`echo "$query_all" | grep 'Capacity alert thresholds' | awk '{print$7}' | sed "s/\r//"`

ret=0

if [[ "$current_capacity_threshold_high" != "$new_capacity_threshold_high" ]] ; then
  ret=1
  echo "ERROR: Current capacity alert threshold high is expected $new_capacity_thr_high, but got $current_capacity_thr_high"
fi
if [[ "$current_capacity_threshold_critical" != "$new_capacity_threshold_critical" ]] ; then
  ret=2
  echo "ERROR: Current capacity alert threshold high is expected $new_capacity_threshold_critical, but got $current_capacity_threshold_critical"
fi
echo "INFO: Success. New capacity thresholds are $current_capacity_threshold_high and $current_capacity_threshold_critical."

juju remove-service scaleio-mdm
wait_for_removed "scaleio-mdm"

trap - ERR EXIT
exit $ret
