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
    env_num=$1
    failed_tasks=`fuel task | grep -i 'error\|fail'`
    if [[ ! -z "$failed_tasks" ]]; then
        echo $failed_tasks
        fail "Failed to execute task $failed_tasks for env $env_num
    fi
}

function execute_task() {
    env_num=$1
    task=$2
    nodes_list=$3
    tries=$4
    
    fuel --env ${env_num} node --${task} --node ${nodes_list} || fail "Failed to $task nodes $nodes_list"
    wait_running_tasks $tries

    check_failed_tasks $env_num
}

function deploy_changes() {
    env_num=$1
    fuel --env $env_num deploy-changes > /dev/null 2>&1 &
    sleep 5
    wait_running_tasks
    check_failed_tasks $env_num
}

start_from=${1:-0}

fuel_version=$(fuel --version 2>&1 | grep -o '[0-9]\.[0-9]\.[0-9]')
env_name="emc"
device_paths="/dev/vdb,/dev/vdc"
if [[ "$fuel_version" == "8.0.0" ]]; then
    ha_mode_opts=''
else
    ha_mode_opts='--mode ha'
fi

if [[ $start_from == 0 ]]; then
  echo Cleaunp env if exists
  env_num=$(fuel env | awk "/$env_name/ {print(\$1)}")
  if [[ ! -z "$env_num" ]]; then
    fuel env --env $env_num --force remove || fail "Failed to cleanup environment"
    wait_running_tasks
  fi

  release=`fuel rel | awk '/Ubuntu/ {print($1)}'`
  if [[ -z "$release" ]]; then
    fail "There is no Ubuntu release"
  fi
  env_num=`fuel env create --name $env_name --release $release ${ha_mode_opts} | grep -Po "(?<=id=)[0-9]+"`
  if [[ -z "$env_num" ]]; then
    fail "Failed to create environment"
  fi

  echo wait nodes online
  
  nodes=()
  for i in {1..60}; do
    nodes=($(fuel node | grep 'True' | awk '/discover/ {if($8=="None"){print($1)}}' | sort))
    if [[ ${#nodes[@]} == 6 || ${#nodes[@]} > 6  ]]; then
        break
    fi
    sleep 10
  done
  if [[ ${#nodes[@]} < 6 ]]; then
    fail "There is not enough free online nodes, only $nodes is available but 6 is required"
  fi
else
  env_num=$(fuel env | awk "/$env_name/ {print(\$1)}")
  nodes=($(fuel node | grep 'True' | awk "/^[0-9]/ {if(\$8==$env_num){print(\$1)}}" | sort))
  nodes+=($(fuel node | grep 'True' | awk "{if(\$8==\"None\"){print(\$1)}}" | sort))
fi

echo nodes: ${nodes[@]}

if [[ $start_from < 2 ]]; then
  # configure nodes: disks and network
  for i in {0..3}; do
    if [[ $i != 3 ]]; then
        roles="cinder,controller"
    else
        roles="compute"
    fi
    
    add_node $env_num ${nodes[$i]} $roles ${device_paths}
  done

  # prepare plugin settings
  fuel --env $env_num settings --download || fail "Failed to download env settings"
  python ${my_dir}/set_plugin_parameters.py --fuel_version "${fuel_version}" --config_file "./settings_${env_num}.yaml" --device_paths ${device_paths} --sds_on_controller=true || fail "Failed to set plugin parameters"
  fuel --env $env_num settings --upload || fail "Failed to download env settings"
fi

if [[ $start_from < 3 ]]; then
  # deploy 3+1 config
  deploy_changes $env_num
fi

if [[ $start_from < 4 ]]; then
  # remove controller: 2+1
  fuel --env $env_num node --node-id ${nodes[0]} remove || fail "Failed to remove node ${nodes[$0]} from environment $env_num"
  deploy_changes $env_num
fi

#update nodes list
nodes=($(fuel node | grep 'True' | awk "/^[0-9]/ {if(\$8==$env_num){print(\$1)}}" | sort))
nodes+=($(fuel node | grep 'True' | awk "{if(\$8==\"None\"){print(\$1)}}" | sort))

if [[ $start_from < 5 ]]; then
  # add controller back: 3+1
  add_node $env_num ${nodes[3]} 'cinder,controller' ${device_paths}
  deploy_changes $env_num
fi

if [[ $start_from < 6 ]]; then
  # add 2 controllers: 5+1
  add_node $env_num ${nodes[4]} 'cinder,controller' ${device_paths}
  add_node $env_num ${nodes[5]} 'cinder,controller' ${device_paths}
  deploy_changes $env_num
fi

cleanup

