#!/bin/bash -e

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

source $my_dir/../functions
source $my_dir/../scaleio/static-checks

echo "--------------------------------------------------------------------------- $(date)"
echo "--------------------------------------------------------------------------- start"

# create machines
echo "Create machines"
m1=$(create_machine 0 0)
echo "Machine created: $m1"
m2=$(create_machine 0 0)
echo "Machine created: $m2"
m3=$(create_machine 0 0)
echo "Machine created: $m3"
m4=$(create_machine 0 0)
echo "Machine created: $m4"
m5=$(create_machine 0 0)
echo "Machine created: $m5"

wait_for_machines $m1 $m2 $m3 $m4 $m5
apply_developing_puppets $m1 $m2 $m3 $m4 $m5
fix_kernel_drivers $m1 $m2 $m3 $m4 $m5

# deploy fake charms to prevent machines removing
juju-deploy ubuntu --to $m1
juju-add-unit ubuntu --to $m2
juju-add-unit ubuntu --to $m3
juju-add-unit ubuntu --to $m4
juju-add-unit ubuntu --to $m5


echo "--------------------------------------------------------------------------- $(date)"
echo "--------------------------------------------------------------------------- full status at start"
juju-status-tabular

master_mdm=''

trap 'catch_errors $LINENO' ERR
function catch_errors() {
  local exit_code=$?
  echo "Line: $1  Error=$exit_code  Command: '$(eval echo $BASH_COMMAND)'"
  trap - ERR

  juju-ssh $master_mdm "sudo scli --query_cluster --approve_certificate" 2>/dev/null

  exit $exit_code
}

function check_mode() {
  master_mdm=`get_master_mdm`
  mode=`juju-ssh $master_mdm "sudo scli --query_cluster --approve_certificate" 2>/dev/null | grep -A 1 "Cluster:" | grep "Mode:" | awk '{print $2}' | sed "s/,//"`
  if [[ "$mode" != $1 ]] ; then
    return 1
  fi
  return 0
}

function check_synced() {
  master_mdm=`get_master_mdm`
  ! juju-ssh $master_mdm "sudo scli --query_cluster --approve_certificate" 2>/dev/null | grep -q "Status: Not synchronized"
}

function wait_for() {
  local max_iter=30
  # waiting for services
  local iter=0
  while ! $@
  do
    if juju-status | grep "current" | grep -q error ; then
      echo "ERROR: Some services went to error state"
      juju-ssh 0 sudo grep Error /var/log/juju/all-machines.log 2>/dev/null
      echo "---------------------------------------------------------------------------"
      juju-status-tabular
      echo "---------------------------------------------------------------------------"
      return 2
    fi

    echo "Waiting for $@ - $iter/$max_iter"
    if ((iter >= max_iter)); then
      echo "ERROR: Wait timeout."
      juju-status-tabular
      return 1
    fi
    sleep 30
    ((++iter))
  done
}

function wait_and_check() {
  # wait for new status
  wait_for check_mode "$1""_node"
  wait_for check_synced

  wait_status

  echo "--------------------------------------------------------------------------- $(date)"
  echo "--------------------------------------------------------------------------- juju-status"
  juju-status-tabular scaleio-mdm

  master_mdm=`get_master_mdm`
  echo "--------------------------------------------------------------------------- $(date)"
  echo "--------------------------------------------------------------------------- cluster status"
  echo "Master MDM found at $master_mdm"
  juju-ssh $master_mdm sudo scli --query_cluster --approve_certificate 2>/dev/null

  check-cluster "juju-ssh" $master_mdm $1
}

function scale_up() {
  # new cluster mode
  local mode=$1
  # if we want to use spare units we will not add new units
  local new_units=$2
  local old_mode=`juju-get scaleio-mdm cluster-mode`
  echo "--------------------------------------------------------------------------- $(date)"
  echo "--------------------------------------------------------------------------- Scale MDM's count up from $old_mode to $mode"
  if (( new_units > 0 )) ; then
    declare -a free_machines
    local mdm_machines=`get_mdm_machines`
    for mch in $m1 $m2 $m3 $m4 $m5 ; do
      if ! echo "$mdm_machines" | grep -qe "^[\t ]*$mch[\t ]*$" ; then
        free_machines=(${free_machines[@]} $mch)
      fi
    done
    echo "Found free machines: "${free_machines[@]}
    local index=0
    local fm_length=${#free_machines[@]}
    while (( index < fm_length && index < new_units )) ; do
      juju-add-unit scaleio-mdm --to ${free_machines[$index]}
      ((++index))
    done
    if (( index < new_units )) ; then
      echo "WARNING: There are no enough machines!!!"
      (( rest = new_units - index ))
      juju-add-unit scaleio-mdm -n $rest
    fi
  fi
  juju-set scaleio-mdm cluster-mode=$mode
  wait_and_check $mode
}

function scale_down() {
  # new cluster mode
  local mode=$1
  shift

  local old_mode=`juju-get scaleio-mdm cluster-mode`
  echo "--------------------------------------------------------------------------- $(date)"
  echo "--------------------------------------------------------------------------- Scale MDM's count down from $old_mode to $mode"

  local output=`juju-ssh $master_mdm "sudo scli --query_cluster --approve_certificate" 2>/dev/null`
  while (( "$#" )); do
    mname="$1"
    shift
    mcount="$1"
    shift

    machines=`echo "$output" | grep -A 10 "$mname" | grep "Name:" | head -$mcount | awk '{gsub("[^0-9]","",$2); print $2}'`
    for m in $machines ; do
      mdm="scaleio-mdm/$m"
      echo "Removing $mdm"
      juju-remove-unit "$mdm"
    done
  done
  sleep 10

  juju-set scaleio-mdm cluster-mode=$mode
  sleep 10
  wait_and_check $mode
}

# check one MDM
echo "--------------------------------------------------------------------------- $(date)"
echo "--------------------------------------------------------------------------- Deploy one MDM"
juju-deploy --repository juju-scaleio local:scaleio-mdm --to $m1
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

for (( i=0; i<4; ++i)) ; do
  echo "--------------------------------------------------------------------------- Step $((i+1)) of 4"
  # to 5 (spare unit will be used)
  scale_up 5 3
  # to 1
  scale_down 1 "Master MDM:" 1 "Slave MDMs:" 1
  # 2 spare units should left
  # to 3
  scale_up 3 0
  # to 1
  scale_down 1 "Slave MDMs:" 1
  # 1 spare unit left
done

# to 5 (1 spare unit will be used)
scale_up 5 3
# TODO: remove unit(s) and add unit(s) back


juju-remove-service scaleio-mdm
wait_for_removed "scaleio-mdm"

juju-status-tabular

echo "--------------------------------------------------------------------------- $(date)"
echo "--------------------------------------------------------------------------- end"

trap - ERR

