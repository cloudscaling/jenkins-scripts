#!/bin/bash

set -ex

if [[ -z "$1" ]] ; then
  echo Environment number should be the first argument
  exit -1
fi
env_number=$1

my_dir="$(dirname "$0")"

if [[ "`whoami`" != 'root' ]] ; then
  echo Provisioning should be run under root
  exit -1
fi


virsh list --all | awk "/fuel-[a-z]+-[$env_number].*/ {print \$2}" | xargs -i virsh destroy {}
virsh list --all | awk '/fuel-[a-z]+-[$env_number].*/ {print \$2}' | xargs -i virsh undefine {}
virsh vol-list --pool fuel-images | awk '/fuel-[a-z]+-[$env_number].*/ {print \$1}' | xargs -i virsh vol-delete --pool fuel-images  {}

