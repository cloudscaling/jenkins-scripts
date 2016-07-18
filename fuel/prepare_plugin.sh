#!/bin/bash

set -ux

function fail() {
  echo ERROR: $1
  exit -1
}

yum install -y git createrepo rpm rpm-build git dpkg-devel dpkg-dev
easy_install pip && pip install fuel-plugin-builder

git clone https://github.com/openstack/fuel-plugin-scaleio.git || fail "Failed to clone fuel-plugin-scaleio git repo"

pushd fuel-plugin-scaleio

fpb --build . || fail "Failed to build plugin"

fuel plugins --install $(ls scaleio*) --force || fail "Failed to install plugin"
fuel plugins --sync || fail "Failed to sync plugin tasks"

popd

