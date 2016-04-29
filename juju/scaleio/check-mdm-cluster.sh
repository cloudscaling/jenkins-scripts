#!/bin/bash -ex

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

source $my_dir/../functions

# create machines
echo "Create machines"
m1=$(juju add-machine 2>&1 | awk '{print $3}')
echo "Machine created: $m1"
m2=$(juju add-machine 2>&1 | awk '{print $3}')
echo "Machine created: $m2"
m3=$(juju add-machine 2>&1 | awk '{print $3}')
echo "Machine created: $m3"
m4=$(juju add-machine 2>&1 | awk '{print $3}')
echo "Machine created: $m4"
m5=$(juju add-machine 2>&1 | awk '{print $3}')
echo "Machine created: $m5"

echo "Wait for machines"
for mch in $m1 $m2 $m3 $m4 $m5 ; do
  iter=0
  while ! juju status | grep "\"$mch\"" &>/dev/null ; do
    echo "Waiting for machine $mch - $iter/12"
    if ((iter >= 12)); then
      echo "ERROR: Machine $mch didn't up."
      juju status
      exit 1
    fi
    ((++iter))
    sleep 10
  done
done
echo "Post-Wait for machines for 30 seconds"
sleep 30

# deploy fake charms to prevent machines removing
juju deploy juju deploy "cs:~justin-fathomdb/trusty/empty" --to $m1
juju service add-unit empty --to $m2
juju service add-unit empty --to $m3
juju service add-unit empty --to $m4
juju service add-unit empty --to $m5

master_mdm=''

function get_mode() {
  master_mdm=`get_master_mdm`
  juju ssh $master_mdm sudo scli --query_cluster --approve_certificate 2>/dev/null | grep -A 1 "Cluster:" | grep "Mode:" | awk '{print $2}' | sed "s/,//"
}

function wait_for_mode() {
  check_str="$1"
  local max_iter=${2:-30}
  # waiting for services
  local iter=0
  while [[ $(get_mode) != $check_str ]]
  do
    if juju status | grep "current" | grep error ; then
      echo "ERROR: Some services went to error state"
      juju ssh 0 sudo grep Error /var/log/juju/all-machines.log 2>/dev/null
      echo "---------------------------------------------------------------------------"
      juju status
      echo "---------------------------------------------------------------------------"
      exit 2
    fi

    echo "Waiting for new status ($check_str) - $iter/$max_iter"
    if ((iter >= max_iter)); then
      echo "ERROR: Satus didn't change."
      juju status
      return 1
    fi
    sleep 30
    ((++iter))
  done
}

function wait_and_check() {
  # wait for new status
  wait_for_mode "$1""_node"

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
juju deploy local:trusty/scaleio-mdm --to $m1
wait_and_check 1

function scale_up() {
  # new cluster mode
  local mode=$1
  # if we want to use spare units we will not add new units
  local new_units=$2
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
  local mode=$1
  shift

  echo "--------------------------------------------------------------------------- $(date)"
  echo "------------------------------------------- Scale MDM's count down to $mode ---"
  echo "---------------------------------------------------------------------------"

  local output=`juju ssh $master_mdm "sudo scli --query_cluster --approve_certificate" 2>/dev/null`
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
scale_up 3 0
# to 1
scale_down 1 "Slave MDMs:" 1
# 1 spare unit left should left
juju ssh $master_mdm sudo scli --query_cluster --approve_certificate 2>/dev/null


juju remove-service scaleio-mdm
wait_for_units_removed "scaleio-mdm"

juju status

if [ -n "$errors" ] ; then exit 1 ; fi
