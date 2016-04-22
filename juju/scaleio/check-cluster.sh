#!/bin/bash

SSH=$1
NODE=$2

# Defining controller mode (mode_1, mode_3, mode_5)
controllers=0
if [[ $3 > 4 ]] ; then
  controllers=5
elif [[ $3 > 2 ]] ; then
  controllers=3
elif [[ $3 > 0 ]] ; then
  controllers=1
fi

# Check if all controllers are in cluster and active
echo "---------------------------------------------------------------------------"
echo "------------------------------------------ check controllers in cluster ---"
echo "---------------------------------------------------------------------------"
if [[ `$SSH $NODE scli --query_cluster  --approve_certificate 2>/dev/null | awk '/Active:/ {print($6)}' ` != "${controllers}/${controllers}," ]] ; then
  echo 'Failed. Not all controllers are in cluster or active'
  $SSH $NODE scli --query_cluster --approve_certificate 2>/dev/null 
  exit 1
else
  echo 'Success'
fi

# Check if state of the cluster is "Normal"
echo "---------------------------------------------------------------------------"
echo "-------------------------------------------- check state of the cluster ---"
echo "---------------------------------------------------------------------------"
if [[ `$SSH $NODE scli --query_cluster  --approve_certificate 2>/dev/null | awk '/State:/ {print($4)}' ` != "Normal," ]] ; then
  echo "Failed. State of the cluster isn't Normal"
  $SSH $NODE scli --query_cluster --approve_certificate 2>/dev/null 
  exit 1
else
  echo 'Success'
fi

# Check if all nodes status is "Normal"
echo "---------------------------------------------------------------------------"
echo "---------------------------------------------------------- nodes status ---"
echo "---------------------------------------------------------------------------"
for status in `$SSH $NODE 'scli --query_cluster --approve_certificate' 2>/dev/null | grep "Status" | awk '{print $2}'` ; do
  if [[ "$status" != "Normal," ]] ; then
    echo "Failed. Not all controller statuses are Normal"
    $SSH $NODE scli --query_cluster --approve_certificate 2>/dev/null 
    exit 1
  else
    echo 'Success'
  fi
done

