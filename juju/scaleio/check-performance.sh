#!/bin/bash

SSH=$1
NODE=$2
USERNAME=$3
PASSWORD=$4

echo "---------------------------------------------------------------------------"
echo "---------------------------------- check cluster performance parameters ---"
echo "---------------------------------------------------------------------------"

if ! output=`$SSH $NODE "scli --login --username $USERNAME --password $PASSWORD --approve_certificate >/dev/null ; scli --query_performance_parameters --all_sds --all_sdc" 2>/dev/null` ; then
  echo 'ERROR: The command "scli --query_performance_parameters --all_sds --all_sdc" failed'
  echo "$output"
  exit 1
fi

#Check if all has high_performance
if echo "$output" | grep "Active profile:" | grep -v "high_performance" ; then
  echo 'ERROR: Not all services have high performance profile'
  echo "$output"
  exit 1
fi

echo "Success of checking performance profile"
