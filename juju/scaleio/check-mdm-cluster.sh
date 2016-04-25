#!/bin/bash -e

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

source $my_dir/../functions

master_mdm=''

function wait_and_check() {
  # wait a little for start of changes
  sleep 20
  wait_for_services "executing|blocked|waiting|allocating"

  # check for errors
  if juju status | grep "current" | grep error ; then
    echo "ERROR: Some services went to error state"
    juju ssh 0 sudo grep Error /var/log/juju/all-machines.log 2>/dev/null
    echo "---------------------------------------------------------------------------"
    juju status
    echo "---------------------------------------------------------------------------"
    exit 2
  fi

  echo "--------------------------------------------------------------------------- $(date)"
  echo "----------------------------------------------------------- juju status ---"
  echo "---------------------------------------------------------------------------"
  juju status

  master_mdm=`get_master_mdm`
  echo "--------------------------------------------------------------------------- $(date)"
  echo "-------------------------------------------------------- cluster status ---"
  echo "---------------------------------------------------------------------------"
  echo "Master MDM found at $master_mdm"
  juju ssh $master_mdm sudo scli --query_cluster --approve_certificate 2>/dev/null

  $my_dir/check-cluster.sh "juju ssh" $master_mdm $1
}

cd juju-scaleio

# check one MDM
echo "--------------------------------------------------------------------------- $(date)"
echo "-------------------------------------------------------- Deploy one MDM ---"
echo "---------------------------------------------------------------------------"
juju deploy local:trusty/scaleio-mdm
wait_and_check 1

function scale_up() {
  # new cluster mode
  mode=$1
  # if we want to use spare units we will not add new units
  new_units=$2
  echo "--------------------------------------------------------------------------- $(date)"
  echo "--------------------------------------------- Scale MDM's count up to $mode ---"
  echo "---------------------------------------------------------------------------"
  if (( new_units > 0 )) ; then
    juju service add-unit scaleio-mdm -n $new_units
  fi
  juju set scaleio-mdm cluster-mode=$mode
  wait_and_check $mode
}

function scale_down() {
  # new cluster mode
  mode=$1

  echo "--------------------------------------------------------------------------- $(date)"
  echo "------------------------------------------- Scale MDM's count down to $mode ---"
  echo "---------------------------------------------------------------------------"

  output=`juju ssh '$master_mdm sudo scli --query_cluster --approve_certificate' 2>/dev/null`
  while (( "$#" )); do
    mname="$1"
    shift
    mcount="$1"
    shift

    machines=`echo "$output" | grep -A 10 "$mname" | grep "Name:" | head -$mcount | awk '{print $2}' | sed "s/.*\([0-9]\),/\1/"`
    for m in $machines ; do
      mdm="scaleio-mdm/$m"
      echo "Removing $mdm"
      juju remove-unit "$mdm"
    done
  done

  juju set scaleio-mdm cluster-mode=$mode
  wait_and_check $mode
}

# to 3
scale_up 3 2
# to 5
scale_up 5 2
# to 3
scale_down 3 "Master MDM:" 1 "Tie-Breakers:" 1
# to 1
scale_down 1 "Master MDM:" 1
# 1 spare unit left
# to 5 (spare unit will be used)
scale_up 5 3
# to 1
scale_down 1 "Master MDM:" 1 "Slave MDMs:" 1
# 2 spare units should left
# to 3
scale_up 2 0
# to 1
scale_down 1 "Slave MDMs:" 1
# 1 spare unit left should left
juju ssh $master_mdm sudo scli --query_cluster --approve_certificate 2>/dev/null


juju remove-service scaleio-mdm
wait_for_units_removed "scaleio-mdm"

juju status

if [ -n "$errors" ] ; then exit 1 ; fi
