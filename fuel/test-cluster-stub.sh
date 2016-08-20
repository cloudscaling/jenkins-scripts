#!/bin/bash -e

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

source ${my_dir}/fuel-utils

copy_to_master "${my_dir}/*.sh"
copy_to_master "${my_dir}/*.py"

if [[ "$PLUGIN_VERSION" == "auto" ]]; then
  case $FUEL_VERSION in
    "6.1" | "7.0")
      plugin_tag="fuel-package-v2"
      ;;
    "8.0" | "9.0")
      plugin_tag="master"
      ;;
    *)
      plugin_tag=$PLUGIN_VERSION
      ;;
  esac
else
  plugin_tag=$PLUGIN_VERSION
fi

execute_on_master "export RELEASE_TAG='$PUPPETS_VERSION' FUEL_PLUGIN_TAG='$plugin_tag'; ./prepare_plugin.sh"
execute_on_master './test-cluster.sh 0 3'
if [[ ! "$FUEL_CHECKS" =~ "skip_openstack" ]] ; then
  ${my_dir}/check-openstack-stub.sh
fi
if [[ "$FUEL_CHECKS" =~ "full" ]] ; then
  execute_on_master './test-cluster.sh 3 8'
fi
