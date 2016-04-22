#!/bin/bash

SSH=$1
NODE=$2
USERNAME=$3
PASSWORD=$4

$SSH $NODE "scli --login --username $USERNAME --password $PASSWORD --approve_certificate" >/dev/null 2>/dev/null

echo "---------------------------------------------------------------------------"
echo "---------------------------------------------- check connection of SDCs ---"
echo "---------------------------------------------------------------------------"
# Check if scli --query_all_sdc works
if [[ `$SSH $NODE 'scli --query_all_sdc --approve_certificate' 2>/dev/null ` ]] ; then

  #Check if all SDC are connected
  if [[ `$SSH $NODE 'scli --query_all_sdc --approve_certificate' 2>/dev/null | grep "SDC ID:" | grep -v "State: Connected"` ]] ; then
    echo 'Failed: Not all sdc are connected'
    $SSH $NODE scli --query_all_sdc --approve_certificate 2>/dev/null 
    exit 1
  else
    echo "Success"
  fi
else
  echo 'ERROR: The command "scli --query_all_sdc --approve_certificate" failed'
  $SSH $NODE scli --query_all_sdc --approve_certificate 2>/dev/null 
  exit 1
fi

