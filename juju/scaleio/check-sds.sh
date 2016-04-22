#!/bin/bash -x

SSH=$1
NODE=$2
USERNAME=$3
PASSWORD=$4
DEVICE_PATH=$5

# Check if scli --query_all_sds works
echo "---------------------------------------------------------------------------"
echo "---------------------------------------------- check connection of SDSs ---"
echo "---------------------------------------------------------------------------"
if ! output=`$SSH $NODE "scli --login --username $USERNAME --password $PASSWORD --approve_certificate >/dev/null ; scli --query_all_sds" 2>/dev/null` ; then
  echo 'ERROR: The command "scli --query_all_sds --approve_certificate" failed'
  echo "$output"
  exit 1
fi

#Check if all SDS are connected
if echo "$output" | grep "SDS ID" | grep -v "State: Connected" ; then
  echo 'ERROR: Not all sds are connected'
  echo "$output"
  exit 1
fi

echo "Success. All sds are connected."

rm -f errors
touch errors

# For all nodes check that roles contain SDC Only & SDS Only and path contains defined path
echo "---------------------------------------------------------------------------"
echo "------------------------------------------------------- check SDS nodes ---"
echo "---------------------------------------------------------------------------"
for node_name in $(echo "$output" | grep "SDS ID" | awk '{print $5}') ; do
  node_errors=0
  node_details=`$SSH $NODE "scli --login --username $USERNAME --password $PASSWORD --approve_certificate >/dev/null ; scli --query_sds --sds_name $node_name" 2>/dev/null`
#  role=`echo "$node_details" | grep "Role:"`
#  if  ! [[ "$role" =~ "SDC Only" && "$role" =~ "SDS Only" ]]  ; then
#    ((++node_errors))
#    echo "ERROR: $node_name does not contain required roles" >> errors
#  fi
  if ! [[ `echo "$node_details" | grep "Path:"` =~ "Path: $DEVICE_PATH" ]] ; then
    ((++node_errors))
    echo '------------------------------' >> errors
    echo "ERROR: $node_name does not contain $DEVICE_PATH path" >> errors
  fi
  if [[ $node_errors != 0 ]] ; then
     echo "$node_details" >> errors
  else
    echo "Success checking of $node_name"
  fi
done

if [ -s errors ] ; then
  cat errors
  exit 1
fi
