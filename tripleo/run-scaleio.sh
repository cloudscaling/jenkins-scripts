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


save_logs

if [[ $CLEAN_ENV != 'false' ]] ; then
  cleanup_environment
fi

trap - ERR
