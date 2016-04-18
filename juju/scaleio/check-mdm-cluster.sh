#!/bin/bash -e

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

source $my_dir/../functions

rm -f errors
touch errors

errors=''

function wait_and_check() {
  if ! err=$(wait_for_services "executing|blocked|waiting|allocating") ; then
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
}

function query_cluster() {
  master_mdm=''
  for mch in `juju status scaleio-mdm --format json | jq .machines | jq keys | tail -n +2 | head -n -1 | sed -e "s/[\",]//g"` ; do
    juju ssh $mch sudo scli --query_cluster --approve_certificate 2>/dev/null 1>/dev/null
    if [[ $? == 0 ]] ; then
      master_mdm=$mch
    fi
  done
  echo "Master MDM found at $master_mdm"
  juju ssh $master_mdm sudo scli --query_cluster --approve_certificate 2>/dev/null
}

cd juju-scaleio

# check one MDM
echo "Deploy one MDM"
juju deploy local:trusty/scaleio-mdm
if wait_and_check ; then
  query_cluster
  echo "Scale MDM's count to 3"
  juju service add-unit scaleio-mdm -n 2
  if wait_and_check ; then
    echo "Scale MDM's count to 5"
    juju service add-unit scaleio-mdm -n 2
    if wait_and_check ; then
      echo "Scale MDM's count back to 3"
      juju remove-unit scaleio-mdm/1
      juju remove-unit scaleio-mdm/2
      wait_and_check
    fi
  fi
fi

juju remove-service scaleio-mdm
wait_for_units_removed "scaleio-mdm"

juju status


if [ -n "$errors" ] ; then exit 1 ; fi
