#!/bin/bash -e

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

source $my_dir/../functions

juju deploy juju-gui --to 0
juju expose juju-gui
juju status

cd juju-scaleio

# this script will change current bundle and it must be called here...
$my_dir/fix_scini_problems.sh

if [ -n "$VERSION" ] ; then
  echo "Change version to $VERSION"
  sed -i -e "s/\"$BUNDLE_VERSION\"/\"$VERSION\"/m" $BUNDLE
fi

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
