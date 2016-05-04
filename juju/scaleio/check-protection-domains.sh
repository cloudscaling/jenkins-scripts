#!/bin/bash -e

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

source $my_dir/../functions

errors=''

function wait_and_check() {
  # wait a little for start of changes
  sleep 20
  if ! err=$(wait_for_services "executing|blocked|waiting|allocating" 50) ; then
    echo $err
    errors+='F'
    return 1
  fi
  # check for errors
  if juju status | grep "current" | grep error ; then
    echo "ERROR: Some services went to error state"
    juju ssh 0 sudo grep Error /var/log/juju/all-machines.log 2>/dev/null
    errors+='F'
    return 2
  fi
  echo "---------------------------------------------------------------------------"
  echo "----------------------------------------------------------- juju status ---"
  echo "---------------------------------------------------------------------------"
  juju status

  master_mdm=`get_master_mdm`
  echo "---------------------------------------------------------------------------"
  echo "-------------------------------------------------------- cluster status ---"
  echo "---------------------------------------------------------------------------"
  echo "Master MDM found at $master_mdm"
  juju ssh $master_mdm sudo scli --query_cluster --approve_certificate 2>/dev/null

  $my_dir/check-cluster.sh "juju ssh" $master_mdm $1
}

cd juju-scaleio

m1=$(juju add-machine --constraints "instance-type=i2.2xlarge" 2>&1 | awk '{print $3}')
echo "Machine created: $m1"
#m2=$(juju add-machine --constraints "instance-type=i2.2xlarge" 2>&1 | awk '{print $3}')
#echo "Machine created: $m2"


# check one MDM
echo "---------------------------------------------------------------------------"
echo "-------------------------------------------------------- Deploy one MDM ---"
echo "---------------------------------------------------------------------------"
juju deploy local:trusty/scaleio-mdm --to $m1
if wait_and_check 1 ; then
  echo "---------------------------------------------------------------------------"
  echo "------------------------------------------------ Deploy first SDS pd1 fs1 ---"
  echo "---------------------------------------------------------------------------"
  juju deploy local:trusty/scaleio-sds --to $m1
  juju set scaleio-sds protection-domain="pd1" fault-set="fs1" storage-pools="sp1,sp2" device-paths="/dev/xvdb,/dev/xvdc"
  juju add-relation scaleio-sds scaleio-mdm
  if wait_and_check 1 ; then
    echo "SUCCESS"

#    echo "---------------------------------------------------------------------------"
#    echo "------------------------------------------------ Deploy second SDS pd2 fs2  ---"
#    echo "---------------------------------------------------------------------------"
#  juju deploy local:trusty/scaleio-sds scaleio-sds-pd2 --to $m2
#  juju set scaleio-sds-pd2 protection-domain="pd2" fault-set="fs2" storage-pools="sp2" device-paths="/dev/xvdc"
#  juju add-relation scaleio-sds-pd2 scaleio-mdm
  fi
fi

#TODO: Check sds protection-domains, fault-sets, storage-pools, device-paths

juju status

if [ -n "$errors" ] ; then exit 1 ; fi
