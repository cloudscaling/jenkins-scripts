#!/bin/bash -e

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

source $my_dir/../functions

rm -f errors
touch errors

errors=''

function wait_and_check() {
  if ! err=$(wait_for_services "executing|blocked|waiting") ; then
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
}

cd juju-scaleio

# check one MDM
echo "Deploy one MDM"
juju deploy local:trusty/scaleio-mdm
if wait_and_check ; then
  echo "Scale MDM's count to 3"
  juju service add-unit scaleio-mdm -n 2
  if wait_and_check ; then
    echo "Scale MDM's count to 5"
    juju service add-unit scaleio-mdm -n 2
  fi
fi

juju remove-service scaleio-mdm
wait_and_check

if [ -n $errors ] ; then exit 1 ; fi
