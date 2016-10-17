#!/bin/bash -e

# common setting from create_env.sh
if [[ -z "$NUM" ]] ; then
  echo "Please set NUM variable to specific environment number. (export NUM=4)"
  exit 1
fi

export NUM
CLEAN_ENV=${CLEAN_ENV:-'true'}
export CLEAN_ENV
PUPPETS_VERSION="${PUPPETS_VERSION:-'master'}"


trap 'catch_errors $LINENO' ERR

function cleanup_environment() {
  sudo -E $WORKSPACE/redhat-kvm/clean_env.sh
}

function save_logs() {
  # save status to file
  echo 'Please save my logs!'
}

function catch_errors() {
  local exit_code=$?
  echo "Line: $1  Error=$exit_code  Command: '$(eval echo $BASH_COMMAND)'"
  trap - ERR

  # sleep some time to flush logs
  sleep 20
  save_logs

  if [[ $CLEAN_ENV != 'false' ]] ; then
    cleanup_environment
  fi

  exit $exit_code
}


if [[ "$PUPPETS_VERSION" != "master" ]] ; then
  sed -i "s/PuppetsVerion: \"master\"/PuppetsVerion: \"$PUPPETS_VERSION\"/g" "$WORKSPACE/redhat-kvm/overcloud/scaleio-env.yaml"
fi
sudo -E $WORKSPACE/redhat-kvm/install_all.sh

BASE_ADDR=${BASE_ADDR:-172}
((env_addr=BASE_ADDR+NUM*10))
ip_addr="192.168.${env_addr}.2"
ssh_opts="-i $my_dir/kp-$NUM -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"
ssh_addr="root@${ip_addr}"
ssh -t $ssh_opts $ssh_addr "sudo -u stack 'cd /home/stack ; git clone https://github.com/cloudscaling/jenkins-scrips ; ./jenkins-scripts/tripleo/check-openstack.sh'"


save_logs

if [[ $CLEAN_ENV != 'false' ]] ; then
  cleanup_environment
fi

trap - ERR
