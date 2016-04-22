#!/bin/bash -e

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

source $my_dir/../functions

errors=''
master_mdm=''

function wait_and_check() {
  # wait a little for start of changes
  sleep 20
  if ! err=$(wait_for_services "executing|blocked|waiting|allocating") ; then
    echo "$err"
    errors+='F'
    return 1
  fi
  # check for errors
  if juju status | grep "current" | grep error ; then
    echo "ERROR: Some services went to error state"
    juju ssh 0 sudo grep Error /var/log/juju/all-machines.log 2>/dev/null
    echo "---------------------------------------------------------------------------"
    juju status
    echo "---------------------------------------------------------------------------"
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

# check one MDM
echo "---------------------------------------------------------------------------"
echo "-------------------------------------------------------- Deploy one MDM ---"
echo "---------------------------------------------------------------------------"
juju deploy local:trusty/scaleio-mdm
if wait_and_check 1 ; then
  echo "---------------------------------------------------------------------------"
  echo "------------------------------------------------ Scale MDM's count to 3 ---"
  echo "---------------------------------------------------------------------------"
  juju service add-unit scaleio-mdm -n 2
  juju set scaleio-mdm cluster-mode=3
  if wait_and_check 3 ; then
    echo "---------------------------------------------------------------------------"
    echo "------------------------------------------------ Scale MDM's count to 5 ---"
    echo "---------------------------------------------------------------------------"
    juju service add-unit scaleio-mdm -n 2
    juju set scaleio-mdm cluster-mode=5
    if wait_and_check 5 ; then
      echo "---------------------------------------------------------------------------"
      echo "------------------------------------------- Scale MDM's count back to 3 ---"
      echo "---------------------------------------------------------------------------"
      output=`juju ssh $master_mdm sudo scli --query_cluster --approve_certificate`
      mdm1=`echo "$oo" | grep -A 1 "Master MDM" | grep "Name:" | awk '{print $2}' | sed "s/,//"`
      mdm2=`echo "$oo" | grep -A 1 "Tie-Breakers" | grep "Name:" | awk '{print $2}' | sed "s/,//"`
      juju remove-unit $mdm1
      juju remove-unit $mdm2
      juju set scaleio-mdm cluster-mode=3
      wait_and_check 3
    fi
  fi
fi

juju remove-service scaleio-mdm
wait_for_units_removed "scaleio-mdm"

juju status

if [ -n "$errors" ] ; then exit 1 ; fi
