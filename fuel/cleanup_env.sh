#!/bin/bash

set -eux

my_dir="$(dirname "$0")"

if [[ "`whoami`" != 'root' ]] ; then
  echo Provisioning should be run under root
  exit -1
fi

pushd ${my_dir}/fuel-kvm
./manage.sh cleanup
popd

