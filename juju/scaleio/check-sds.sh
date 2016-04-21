#!/bin/bash

SSH=$1
NODE=$2
USERNAME=$3
PASSWORD=$4
DEVICE_PATH=$5

rm -f errors
touch errors

$SSH $NODE "scli --login --username $USERNAME --password $PASSWORD --approve_certificate" >/dev/null 2>/dev/null

# Check if scli --query_all_sds works
echo "---------------------------------------------------------------------------"
echo "---------------------------------------------- check connection of SDSs ---"
echo "---------------------------------------------------------------------------"
if [[ `$SSH $NODE 'scli --query_all_sds --approve_certificate' 2>/dev/null ` ]] ; then

  #Check if all SDS are connected
  if [[ `$SSH $NODE 'scli --query_all_sds --approve_certificate' 2>/dev/null | grep "SDS ID" | grep -v "State: Connected"` ]] ; then
    echo 'Failed. Not all sds are connected' >> errors
    $SSH $NODE 'scli --query_all_sds --approve_certificate'
    exit 1
  else
    echo "Success"
  fi
else
  echo 'ERROR: The command "scli --query_all_sds --approve_certificate" failed' >> errors
  $SSH $NODE 'scli --query_all_sds --approve_certificate'
  exit 1
fi

# For all nodes check that roles contain SDC Only & SDS Only and path contains defined path
echo "---------------------------------------------------------------------------"
echo "------------------------------------------------------- check SDS nodes ---"
echo "---------------------------------------------------------------------------"
for node_name in $($SSH $NODE 'scli --query_all_sds --approve_certificate' 2>/dev/null | grep "SDS ID" | awk '{print $5}') ; do 
  node_errors=0
  role=`$SSH $NODE "scli --query_sds --sds_name $node_name " 2>/dev/null | grep Role: `
  if  ! [[ "$role" =~ "SDC Only" && "$role" =~ "SDS Only" ]]  ; then
    ((++node_errors))
    echo "Failed. $node_name does not contain required roles" >> errors
  fi
  if ! [[ `$SSH $NODE "scli --query_sds --sds_name $node_name " 2>/dev/null | grep Path: ` =~ "Path: $DEVICE_PATH" ]] ; then
    ((++node_errors))
    echo '------------------------------' >> errors
    echo "Failed. $node_name does not contain $DEVICE_PATH path" >> errors
  fi
  if [[ $node_errors != 0 ]] ; then
     $SSH $NODE "scli --query_sds --sds_name $node_name " >> errors
  else
    echo 'Success'
  fi
done

if [ -s errors ] ; then
  cat errors
  exit 1
fi
