#!/bin/bash -e

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

source $my_dir/../functions

juju deploy juju-gui --to 0
juju expose juju-gui
juju status

cd juju-scaleio

# ---------------------------------------- juju-deployer hack start
# due to inability to create instances with additional disks via bundle
# script will create machines before bundle
m1=$(create_machine 1 0)
echo "Machine created: $m1"
m2=$(create_machine 1 0)
echo "Machine created: $m2"
m3=$(create_machine 0 1)
echo "Machine created: $m3"
m4=$(create_machine 0 1)
echo "Machine created: $m4"
m5=$(create_machine 0 1)
echo "Machine created: $m5"

wait_for_machines $m1 $m2 $m3 $m4 $m5

# change machine name in bundle to numbers
sed -i -e "s/\"compute-1\"/\"$m1\"/m" $BUNDLE
sed -i -e "s/\"compute-2\"/\"$m2\"/m" $BUNDLE
sed -i -e "s/\"io-1\"/\"$m3\"/m" $BUNDLE
sed -i -e "s/\"io-2\"/\"$m4\"/m" $BUNDLE
sed -i -e "s/\"io-3\"/\"$m5\"/m" $BUNDLE
sed -i -e "s/xvdb/xvdf/m" $BUNDLE
# ---------------------------------------- juju-deployer hack end

$my_dir/fix_scini_problems.sh $m1 $m2

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
