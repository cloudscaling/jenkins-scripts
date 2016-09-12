#!/bin/bash

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

set -ux

function cleanup() {
    rm -rf ./node_*
    rm -f *.yaml
}

function fail() {
    cleanup
    echo "Error: $1"
    exit -1
}

function add_node() {
    local env_num=$1
    local node_id=$2
    local roles=$3
    local device_paths=$4
    
    if [[ ! -z "`echo $roles | grep controller`" ]]; then
        local is_controller_opts='--is_controller=true'
    else
        local is_controller_opts=''
    fi
   
    local query=`echo $roles | sed 's/,/, /g'`
    fuel node --node-id $node_id | grep "^$node_id" | grep -q "$query" || fuel node set --env $env_num --node $node_id --role "$roles" || fail "Failed to add node"

    node_opts="node --node-id ${node_id}"
    base_dir="./node_${node_id}"
    
    fuel $node_opts --disk --download || fail "Failed to download node ${node_id} disk settings"
    python ${my_dir}/set_node_volumes_layout.py --config_file "${base_dir}/disks.yaml" --device_paths ${device_paths} ${is_controller_opts} || fail "Failed to patch node ${node_id} disk layout"
    fuel $node_opts --disk --upload || fail "Failed to upload node  ${node_id} disk settings"    

    fuel $node_opts --network --download || fail "Failed to download node network settings"
    python ${my_dir}/set_node_network.py --config_file "${base_dir}/interfaces.yaml" || fail "Failed to patch node ${node_id} network config"
    fuel $node_opts --network --upload || fail "Failed to upload node  ${node_id} network settings"
}

function wait_running_tasks() {
    tries=${1:-360}
    pause_time=${2:-30}
    ((count=0))
    while(($count < $tries)); do
        if [[ -z "`fuel task | grep 'running'`" ]]; then
            return 0
        fi
        ((count++))
        echo wait $count/$tries
        sleep $pause_time
    done

    fail "Error: timeout"
}

function check_failed_tasks() {
    local env_num=$1
    local failed_tasks=`fuel task | grep -i 'error\|fail'`
    if [[ ! -z "$failed_tasks" ]]; then
        echo $failed_tasks
        fail "Failed to execute task $failed_tasks for env $env_num"
    fi
}

function execute_task() {
    local env_num=$1
    local task=$2
    local nodes_list=$3
    local tries=$4
    
    fuel --env ${env_num} node --${task} --node ${nodes_list} || fail "Failed to $task nodes $nodes_list"
    wait_running_tasks $tries

    check_failed_tasks $env_num
}

function deploy_changes() {
    local env_num=$1
    fuel --env $env_num deploy-changes > /dev/null 2>&1 &
    local pid="$!"
    local tries=360
    while [[ $tries > 0 ]] ; do
      echo wait $tries
      if ! ps $pid ; then
        break
      fi
      tries=$((tries-1))
      sleep 30
    done
    wait_running_tasks
    check_failed_tasks $env_num
}

function list_online_nodes() {
  local env=$1
  local role=${2:-""}
  local role_regexp=""
  if [[ "$env" == "None" && "$fuel_version" == "9.0.0" ]] ; then
    env=""
  fi
  if [ -n "$role" ] ; then
    role_regexp=".*${role}.*"
  fi
  fuel node | awk -F '|' "/^[ ]*[0-9]+[ |]+${role_regexp}/ {
    gsub(/[ \t\r\n]+/, \"\", \$1); \
    gsub(/[ \t\r\n]+/, \"\", \$9); \
    gsub(/[ \t\r\n]+/, \"\", \$4); \
    if((\$9==\"True\" || \$9==\"1\") && \$4==\"$env\"){print(\$1)}}" | sort
}

function update_nodes() {
   echo wait nodes online
   for i in {1..60}; do
    # nodes and env_num are global vars
    nodes=($(list_online_nodes $env_num 'controller'))
    nodes+=($(list_online_nodes $env_num 'compute'))
    nodes+=($(list_online_nodes 'None'))
    if [[ ${#nodes[@]} == 6 || ${#nodes[@]} > 6  ]]; then
        break
    fi
    sleep 10
  done
  echo online nodes: ${nodes[@]}
  if [[ ${#nodes[@]} < 6 ]]; then
    fail "There is not enough free online nodes, only ${#nodes[@]} is available but 6 is required"
  fi
}

start_from=${1:-0}
end_to=${2:-8}
steps_count=$((end_to-start_from))

if (( ${steps_count} < 1 )) ; then
  echo "No more steps to execute"
  exit 0
fi

fuel_env_number=${FUEL_ENV_NUMBER:-'0'}

fuel_version=$(fuel --version 2>&1 | grep -o '[0-9]\.[0-9]\.[0-9]')
env_name="emc"
device_paths="/dev/vdb,/dev/vdc"
if [[ "$fuel_version" == "8.0.0" || "$fuel_version" == "9.0.0" ]]; then
    ha_mode_opts=''
else
    ha_mode_opts='--mode ha'
fi
nodes=()
env_num=$(fuel env | awk "/$env_name/ {print(\$1)}")

if [[ $start_from < 1 ]]; then
  echo Cleaunp env if exists
  if [[ ! -z "$env_num" ]]; then
    fuel env --env $env_num --force remove || fail "Failed to cleanup environment"
    wait_running_tasks
  fi

  release=`fuel rel | awk '/Ubuntu [0-9]+/ {print($1)}'`
  if [[ -z "$release" ]]; then
    fail "There is no Ubuntu release"
  fi
  env_num=`fuel env create --name $env_name --release $release ${ha_mode_opts} | grep -Po "(?<=id=)[0-9]+"`
  if [[ -z "$env_num" ]]; then
    fail "Failed to create environment"
  fi

  steps_count=$((steps_count-1))
fi

update_nodes

if (( ${steps_count} < 1 )) ; then
  echo "No more steps to execute"
  exit 0
fi

if [[ $start_from < 2 ]]; then
  # configure nodes: disks and network
  for i in {0..4}; do
    if [[ $i < 3 ]]; then
        roles="cinder,controller"
    else
        roles="compute"
    fi

    add_node $env_num ${nodes[$i]} $roles ${device_paths}
  done

  # prepare plugin settings
  fuel --env $env_num settings --download || fail "Failed to download env settings"
  python ${my_dir}/set_plugin_parameters.py --fuel_version "${fuel_version}" --config_file "./settings_${env_num}.yaml" --device_paths ${device_paths} --sds_on_controller=true || fail "Failed to set plugin parameters"
  fuel --env $env_num settings --upload || fail "Failed to upload env settings"

  # prepare network settings
  fuel --env $env_num network --download || fail "Failed to download network settings"
  python ${my_dir}/set_network_parameters.py --fuel_version "${fuel_version}" --config_file "./network_${env_num}.yaml" --env_number $fuel_env_number || fail "Failed to set network parameters"
  cat ./network_${env_num}.yaml
  fuel --env $env_num network --upload || fail "Failed to upload network settings"

  steps_count=$((steps_count-1))
fi

if (( ${steps_count} < 1 )) ; then
  echo "No more steps to execute"
  exit 0
fi

if [[ $start_from < 3 ]]; then
  # deploy 3+2 config
  deploy_changes $env_num
  steps_count=$((steps_count-1))
fi

if (( ${steps_count} < 1 )) ; then
  echo "No more steps to execute"
  exit 0
fi

if [[ $start_from < 4 ]]; then
  # remove controller: 2+2
  fuel --env $env_num node --node-id ${nodes[0]} remove || fail "Failed to remove node ${nodes[0]} from environment $env_num"
  deploy_changes $env_num
  steps_count=$((steps_count-1))
  update_nodes
fi

if (( ${steps_count} < 1 )) ; then
  echo "No more steps to execute"
  exit 0
fi

if [[ $start_from < 5 ]]; then
  # add controller back: 3+2
  add_node $env_num ${nodes[4]} 'cinder,controller' ${device_paths}
  deploy_changes $env_num
  steps_count=$((steps_count-1))
fi

if (( ${steps_count} < 1 )) ; then
  echo "No more steps to execute"
  exit 0
fi

if [[ $start_from < 6 ]]; then
  # remove compute: 3+1
  fuel --env $env_num node --node-id ${nodes[3]} remove || fail "Failed to remove node ${nodes[3]} from environment $env_num"
  deploy_changes $env_num
  steps_count=$((steps_count-1))
  update_nodes
fi

if (( ${steps_count} < 1 )) ; then
  echo "No more steps to execute"
  exit 0
fi

if [[ $start_from < 7 ]]; then
  # add 2 controllers: 5+1
  add_node $env_num ${nodes[4]} 'cinder,controller' ${device_paths}
  add_node $env_num ${nodes[5]} 'cinder,controller' ${device_paths}
  deploy_changes $env_num
  steps_count=$((steps_count-1))
fi

if (( ${steps_count} < 1 )) ; then
  echo "No more steps to execute"
  exit 0
fi

if [[ $start_from < 8 ]]; then
  cleanup
  steps_count=$((steps_count-1))
fi

