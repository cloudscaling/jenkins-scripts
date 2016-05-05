#!/bin/bash -e

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

source $my_dir/../functions

echo "--------------------------------------------------------------------------- $(date)"
echo "----------------------------------------------------------------- start ---"
echo "---------------------------------------------------------------------------"

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

wait_for_machines $m1 $m2 $m3 $m4 $m5

# deploy fake charms to prevent machines removing
juju deploy --repository $my_dir/../empty-charm  local:trusty/empty-charm --to $m1
juju service add-unit empty-charm --to $m2
juju service add-unit empty-charm --to $m3
juju service add-unit empty-charm --to $m4
juju service add-unit empty-charm --to $m5


echo "--------------------------------------------------------------------------- $(date)"
echo "-------------------------------------------------- full status at start ---"
echo "---------------------------------------------------------------------------"
juju status

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
    if juju status | grep "current" | grep error >/dev/null ; then
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
  if juju status | grep "current" | grep error >/dev/null ; then
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
  juju status scaleio-mdm

  master_mdm=`get_master_mdm`
  echo "--------------------------------------------------------------------------- $(date)"
  echo "-------------------------------------------------------- cluster status ---"
  echo "---------------------------------------------------------------------------"
  echo "Master MDM found at $master_mdm"
  juju ssh $master_mdm sudo scli --query_cluster --approve_certificate 2>/dev/null

  $my_dir/check-cluster.sh "juju ssh" $master_mdm $1
}

function scale_up() {
  # new cluster mode
  local mode=$1
  # if we want to use spare units we will not add new units
  local new_units=$2
  local old_mode=`get_cluster_mode`
  echo "--------------------------------------------------------------------------- $(date)"
  echo "-------------------------------------- Scale MDM's count up from $old_mode to $mode ---"
  echo "---------------------------------------------------------------------------"
  if (( new_units > 0 )) ; then
    declare -a free_machines
    local mdm_machines=`get_mdm_machines`
    for mch in $m1 $m2 $m3 $m4 $m5 ; do
      if ! echo "$mdm_machines" | grep -e "^[\t ]*$mch[\t ]*$" >/dev/null ; then
        free_machines=(${free_machines[@]} $mch)
      fi
    done
    echo "Found free machines: "${free_machines[@]}
    local index=0
    local fm_length=${#free_machines[@]}
    while (( index < fm_length && index < new_units )) ; do
      juju service add-unit scaleio-mdm --to ${free_machines[$index]}
      ((++index))
    done
    if (( index < new_units )) ; then
      echo "WARNING: There are no enough machines!!!"
      (( rest = new_units - index ))
      juju service add-unit scaleio-mdm -n $rest
    fi
  fi
  juju set scaleio-mdm cluster-mode=$mode
  wait_and_check $mode
}

function scale_down() {
  # new cluster mode
  local mode=$1
  shift

  local old_mode=`get_cluster_mode`
  echo "--------------------------------------------------------------------------- $(date)"
  echo "---------------------------------- Scale MDM's count down from $old_mode to $mode ---"
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

cd juju-scaleio

# check one MDM
echo "--------------------------------------------------------------------------- $(date)"
echo "-------------------------------------------------------- Deploy one MDM ---"
echo "---------------------------------------------------------------------------"
juju deploy local:trusty/scaleio-mdm --to $m1
wait_and_check 1


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

# to 5 (1 spare unit will be used)
scale_up 5 3
# TODO: remove unit(s) and add unit(s) back


juju remove-service scaleio-mdm
wait_for_units_removed "scaleio-mdm"

juju status

echo "--------------------------------------------------------------------------- $(date)"
echo "------------------------------------------------------------------- end ---"
echo "---------------------------------------------------------------------------"
