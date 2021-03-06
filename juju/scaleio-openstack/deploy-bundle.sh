#!/bin/bash -e

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

source $my_dir/../functions

deploy_from=${1:-github}   # Place where to get ScaleIO charms - github or charmstore
if [[ "$deploy_from" == github ]] ; then
  jver="$(juju-version)"
  if [[ "$jver" == 1 ]] ; then
    JUJU_REPO="local:$SERIES"
  else
    # version 2
    JUJU_REPO="$WORKSPACE/juju-scaleio/$SERIES/"
  fi
else
  # deploy_from=charmstore
  JUJU_REPO="cs:~cloudscaling"
fi

BUNDLE="$my_dir/openstack-scaleio-amazon.yaml"
echo "---------------------------------------------------- From: $JUJU_REPO  Version: $VERSION"

# ---------------------------------------- pre-deployment stage start
# due to inability to create instances with additional disks via bundle
# script will create machines before bundle
# also it will upgrade kernel if new machines have kernel that absent on ftp
m1=$(create_machine 1 0)
echo "INFO: Machine created: $m1"
m2=$(create_machine 1 0)
echo "INFO: Machine created: $m2"
m3=$(create_machine 2 1)
echo "INFO: Machine created: $m3"
m4=$(create_machine 2 1)
echo "INFO: Machine created: $m4"
m5=$(create_machine 2 1)
echo "INFO: Machine created: $m5"

wait_for_machines $m1 $m2 $m3 $m4 $m5
apply_developing_puppets $m1 $m2 $m3 $m4 $m5
fix_kernel_drivers $m1 $m2 $m3 $m4 $m5

create_eth1 $m1
create_eth1 $m2
# ---------------------------------------- pre-deployment stage end

# change bundles' variables
echo "INFO: Change OpenStack version in bundle to $VERSION"
sed -i -e "s/%SERIES%/$SERIES/m" $BUNDLE
sed -i -e "s/%VERSION%/$VERSION/m" $BUNDLE
sed -i -e "s|%JUJU_REPO%|$JUJU_REPO|m" $BUNDLE

# script needs to change directory to local charms repository
cd juju-scaleio
juju-deploy-bundle $BUNDLE

echo "INFO: Wait for services start: $(date)"
wait_absence_status_for_services "executing|blocked|waiting"
echo "INFO: Wait for services end: $(date)"

# check for errors
if juju-status | grep "current" | grep error ; then
  echo "ERROR: Some services went to error state"
  juju-ssh 0 sudo grep Error /var/log/juju/all-machines.log 2>/dev/null
  exit 1
fi

echo "INFO: Waiting for all services up"
sleep 60
