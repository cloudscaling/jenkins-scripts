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

# fix security group 'juju-amazon'
# TODO: another bug somewhere
group_id=`aws ec2 describe-security-groups --group-name juju-amazon --query 'SecurityGroups[0].GroupId' --output text`
aws ec2 revoke-security-group-ingress --group-name juju-amazon --protocol tcp  --port 0-65535 --source-group $group_id
aws ec2 authorize-security-group-ingress --group-name juju-amazon --protocol tcp --cidr "0.0.0.0/0" --port 0-65535

# check for errors
if juju status | grep "current" | grep error ; then
  echo "ERROR: Some services went to error state"
  juju ssh 0 sudo grep Error /var/log/juju/all-machines.log 2>/dev/null
  exit 1
fi

echo "Waiting for all services up"
sleep 60
