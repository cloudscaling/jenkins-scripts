#!/bin/bash

set -ux

function fail() {
  echo ERROR: $1
  exit -1
}

yum install -y git createrepo rpm rpm-build git dpkg-devel dpkg-dev
easy_install --upgrade pip && pip install fuel-plugin-builder

rm -rf fuel-plugin-scaleio
git clone https://github.com/openstack/fuel-plugin-scaleio.git || fail "Failed to clone fuel-plugin-scaleio git repo"

pushd fuel-plugin-scaleio

if [[ -n "$FUEL_PLUGIN_TAG" ]]; then
  echo "INFO: Fuel plugin tag is '$FUEL_PLUGIN_TAG'"
  if git tag -l | grep -q "$FUEL_PLUGIN_TAG" ; then
      git checkout "tags/$FUEL_PLUGIN_TAG"
  else
      git checkout "$FUEL_PLUGIN_TAG"
  fi
fi

echo "INFO: Release tag for plugin is '$RELEASE_TAG'"
fpb --build . || fail "Failed to build plugin"

fuel plugins --install $(ls scaleio*) --force || fail "Failed to install plugin"
fuel plugins --sync || fail "Failed to sync plugin tasks"

popd

