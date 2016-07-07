#!/bin/bash -e

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

source $my_dir/../functions
source $my_dir/functions

deploy_from=${1:-charmstore}   # Place where to get ScaleIO charms - github or charmstore
if [[ "$deploy_from" == charmstore ]] ; then
  JUJU_REPO="cs:~cloudscaling"
else
  # deploy_from=github
  JUJU_REPO="local:trusty"
fi

BUNDLE="$my_dir/scaleio-amazon.yaml"
echo "---------------------------------------------------- From: $JUJU_REPO "

juju status --format tabular

# ---------------------------------------- pre-deployment stage start
# due to inability to create instances with additional disks via bundle
# script will create machines before bundle
# also it will upgrade kernel if new machines have kernel that absent on ftp
m1=$(create_machine 2 1)
echo "Machine created: $m1"
m2=$(create_machine 2 1)
echo "Machine created: $m2"
m3=$(create_machine 2 1)
echo "Machine created: $m3"

wait_for_machines $m1 $m2 $m3

$my_dir/fix_scini_problems.sh $m1 $m2 $m3

# ---------------------------------------- pre-deployment stage end

# change bundles' variables
sed -i -e "s/%JUJU_REPO%/$JUJU_REPO/m" $BUNDLE

# script needs to change directory to local charms repository
cd juju-scaleio
juju-deployer -c $BUNDLE

echo "Wait for services start: $(date)"
wait_absence_status_for_services "executing|blocked|waiting"
echo "Wait for services end: $(date)"

# check for errors
if juju status | grep "current" | grep error ; then
  echo "ERROR: Some services went to error state"
  juju ssh 0 sudo grep Error /var/log/juju/all-machines.log 2>/dev/null
  exit 1
fi

echo "Waiting for all services up"
sleep 60
