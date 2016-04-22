#!/bin/bash

SSH=$1
NODE=$2
controllers=$3

# Check if all controllers are in cluster and active
echo "---------------------------------------------------------------------------"
echo "------------------------------------------ check controllers in cluster ---"
echo "---------------------------------------------------------------------------"
if [[ `$SSH $NODE scli --query_cluster  --approve_certificate 2>/dev/null | awk '/Active:/ {print($6)}' ` != "${controllers}/${controllers}," ]] ; then
  echo 'ERROR: Not all controllers are in cluster or active'
  $SSH $NODE scli --query_cluster --approve_certificate 2>/dev/null 
  exit 1
fi
echo 'Success. All controllers are in cluster or active.'

# Check if state of the cluster is "Normal"
echo "---------------------------------------------------------------------------"
echo "-------------------------------------------- check state of the cluster ---"
echo "---------------------------------------------------------------------------"
if [[ `$SSH $NODE scli --query_cluster  --approve_certificate 2>/dev/null | awk '/State:/ {print($4)}' ` != "Normal," ]] ; then
  echo "ERROR: State of the cluster isn't Normal"
  $SSH $NODE scli --query_cluster --approve_certificate 2>/dev/null 
  exit 1
fi
echo 'Success. State of the cluster is Normal'

# Check if all nodes status is "Normal"
echo "---------------------------------------------------------------------------"
echo "---------------------------------------------------- check nodes status ---"
echo "---------------------------------------------------------------------------"
for status in `$SSH $NODE 'scli --query_cluster --approve_certificate' 2>/dev/null | grep "Status" | awk '{print $2}'` ; do
  if [[ "$status" != "Normal," ]] ; then
    echo "ERROR: Not all controller statuses are Normal"
    $SSH $NODE scli --query_cluster --approve_certificate 2>/dev/null 
    exit 1
  fi
done
echo 'Success. All controller statuses are Normal'

