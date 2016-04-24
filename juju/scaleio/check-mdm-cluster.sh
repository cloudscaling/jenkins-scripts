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
wait_and_check 1

function scale_up() {
  count=${1:-2}
  mode=`get_cluster_mode`
  ((mode = mode + count))
  echo "---------------------------------------------------------------------------"
  echo "----------------------------------------- Scale MDM's count up to $mode ---"
  echo "---------------------------------------------------------------------------"
  juju service add-unit scaleio-mdm -n 2
  juju set scaleio-mdm cluster-mode=$mode
  wait_and_check $mode
}

function scale_down() {
  output=`juju ssh $master_mdm sudo scli --query_cluster --approve_certificate`

  mode=5
  while (( "$#" )); do
    $mname=$1
    shift
    $mcount=$1
    shift

    machines=`echo "$output" | grep -A 10 "$mname" | grep "Name:" | head -$mcount | awk '{print $2}' | sed "s/.*\([0-9]\),/\1/"`
    for m in $machines ; do
      mdm="scaleio-mdm/$m"
      echo "Removing $mdm"
      juju remove-unit "$mdm"
      ((--mode))
    done
  done

  juju set scaleio-mdm cluster-mode=$mode
  wait_and_check $mode
}

# to 3
scale_up 2
# to 5
scale_up 2
# to 3
scale_down "Master MDM:" 1 "Slave MDMs:" 1
# to 1
scale_down "Master MDM:" 1 "Slave MDMs:" 1
# to 5
scale_up 4
# to 1
scale_down "Master MDM:" 1 "Slave MDMs:" 2 "Tie-Breakers:" 1
# to 3
scale_up 2
# to 1
scale_down "Master MDM:" 1 "Slave MDMs:" 1


juju remove-service scaleio-mdm
wait_for_units_removed "scaleio-mdm"

juju status

if [ -n "$errors" ] ; then exit 1 ; fi
