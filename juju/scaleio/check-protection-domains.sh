#!/bin/bash -e

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

source $my_dir/../functions

cd juju-scaleio

m1=$(juju add-machine --constraints "instance-type=i2.2xlarge" 2>&1 | awk '{print $3}')
echo "Machine created: $m1"
m2=$(juju add-machine --constraints "instance-type=i2.2xlarge" 2>&1 | awk '{print $3}')
echo "Machine created: $m2"


echo "---------------------------------------------------------------------------"
echo "------------------------------------------------------------ Deploy MDM ---"
echo "---------------------------------------------------------------------------"
juju deploy local:trusty/scaleio-mdm --to 0

echo "---------------------------------------------------------------------------"
echo "----------------- Deploy SDS 1 (pd1; fs1; sp1,sp2; /dev/xvdb,/dev/xvdc) ---"
echo "---------------------------------------------------------------------------"
juju deploy local:trusty/scaleio-sds scaleio-sds-pd1 --to $m1
juju set scaleio-sds protection-domain="pd1" fault-set="fs1" storage-pools="sp1,sp2" device-paths="/dev/xvdb,/dev/xvdc"
juju add-relation scaleio-sds scaleio-mdm

echo "---------------------------------------------------------------------------"
echo "----------------- Deploy SDS 2 (pd1; fs1; sp2,sp1; /dev/xvdb,/dev/xvdc) ---"
echo "---------------------------------------------------------------------------"
juju deploy local:trusty/scaleio-sds scaleio-sds-pd2 --to $m2
juju set scaleio-sds-pd2 protection-domain="pd2" fault-set="fs2" storage-pools="sp2,sp1" device-paths="/dev/xvdb,/dev/xvdc"
juju add-relation scaleio-sds-pd2 scaleio-mdm

# wait
wait_for_services "executing|blocked|waiting|allocating"

# check for errors
if juju status | grep "current" | grep error ; then
  echo "ERROR: Some services went to error state"
  juju ssh 0 sudo grep Error /var/log/juju/all-machines.log 2>/dev/null
  exit 1
fi

#TODO: Check sds protection-domains, fault-sets, storage-pools, device-paths

juju status
