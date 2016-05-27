#!/bin/bash -e

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

USERNAME='admin'
PASSWORD="Default_password"

source $my_dir/../functions

cd juju-scaleio

function wait_status() {
wait_absence_status_for_services "executing|blocked|waiting|allocating"
  
# check for errors
if juju status | grep "current" | grep error >/dev/null ; then
  echo "ERROR: Some services went to error state"
  juju ssh 0 sudo grep Error /var/log/juju/all-machines.log 2>/dev/null
  echo "---------------------------------------------------------------------------"
  juju status
  echo "---------------------------------------------------------------------------"
  exit 2
fi
}

echo "---------------------------------------------------------------- Deploy MDM ---"
juju deploy local:trusty/scaleio-mdm --to 0

wait_status

echo "------------------------------------------------------- check mdm password  ---"
if ! mdm_output=`juju ssh 0 "scli --login --username $USERNAME --password $PASSWORD --approve_certificate >/dev/null ; scli --query_all" 2>/dev/null` ; then
  echo "ERROR: Couldn't login or execute 'scli --query_all'"
  echo "$mdm_output"
  exit 1
fi
echo Success

echo "----------------------------------------------------------- change password ---"
new_password="No_password"
juju set scaleio-mdm password=$new_password
sleep 5

echo "----------------------------------------------------------------- wait hook ---"
wait_status

echo "------------------------------------------- check old password doesn't work ---"
if mdm_output=`juju ssh 0 "scli --login --username $USERNAME --password $PASSWORD --approve_certificate >/dev/null " 2>/dev/null` ; then
  echo "ERROR: Could login and execute 'scli --query_all' with old password"
  echo "$mdm_output"
  exit 1
elif [[ "$mdm_output" != *"Permission denied"* ]] ; then
  echo "ERROR: Some error was occured"
  echo "$mdm_output"
  exit 1
fi
echo Success

echo "-------------------------------------------------- check new password works ---"
if ! mdm_output=`juju ssh 0 "scli --login --username $USERNAME --password $new_password --approve_certificate >/dev/null ; scli --query_all" 2>/dev/null` ; then
  echo "ERROR: Couldn't login or execute 'scli --query_all'"
  echo "$mdm_output"
  exit 1
fi
echo Success

# Check capacity alert thresholds

query_all=`juju ssh 0 "scli --login --username $USERNAME --password $PASSWORD --approve_certificate >/dev/null ; scli --query_all" 2>/dev/null`
current_capacity_thr_high=`echo "$query_all" | grep 'Capacity alert thresholds' | awk '{print$5}'`
current_capacity_thr_critical=`echo "$query_all" | grep 'Capacity alert thresholds' | awk '{print$7}'`
echo "Current capacity thresholds are $current_capacity_thr_high and $current_capacity_thr_critical"

new_capacity_thr_high=79
new_capacity_thr_critical=89

echo "------------------------------------------ change capacity alert thresholds ---"
juju set scaleio-mdm capacity-high-alert-threshold="$new_capacity_thr_high" capacity-critical-alert-threshold="$new_capacity_thr_critical"
sleep 5

wait_status

echo "--------------------------------------- check new capacity alert thresholds ---"
query_all=`juju ssh 0 "scli --login --username $USERNAME --password $PASSWORD --approve_certificate >/dev/null ; scli --query_all" 2>/dev/null`
current_capacity_thr_high=`echo "$query_all" | grep 'Capacity alert thresholds' | awk '{print$5}' | sed "s/,//"`
current_capacity_thr_critical=`echo "$query_all" | grep 'Capacity alert thresholds' | awk '{print$7}' | sed "s/\r//"`

if [[ "$current_capacity_thr_high" != "$new_capacity_thr_high" ]] ; then
  echo "ERROR: Current capacity alert threshold high is expected $new_capacity_thr_high, but got $current_capacity_thr_high"
  exit 1
fi
if [[ "$current_capacity_thr_critical" != "$new_capacity_thr_critical" ]] ; then
  echo "ERROR: Current capacity alert threshold high is expected $new_capacity_thr_critical, but got $current_capacity_thr_critical"
  exit 1
fi
echo Success
