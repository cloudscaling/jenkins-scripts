#!/bin/bash

SSH=$1
NODE=$2
USERNAME=$3
PASSWORD=$4

echo "---------------------------------------------------------------------------"
echo "---------------------------------------------- check connection of SDCs ---"
echo "---------------------------------------------------------------------------"

if ! output=`$SSH $NODE "scli --login --username $USERNAME --password $PASSWORD --approve_certificate >/dev/null ; scli --query_all_sdc" 2>/dev/null` ; then
  echo 'ERROR: The command "scli --query_all_sdc --approve_certificate" failed'
  echo "$output"
  exit 1
fi

#Check if all SDS are connected
if echo "$output" | grep "SDC ID" | grep -v "State: Connected" ; then
  echo 'ERROR: Not all sdc are connected'
  echo "$output"
  exit 1
fi

echo "Success. All sdc are connected."
