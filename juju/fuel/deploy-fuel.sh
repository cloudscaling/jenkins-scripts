#!/bin/bash -e

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

source $my_dir/../functions

cdir="$(pwd)"
cd fuel-charms

# this script will change current bundle and it must be called here...
#$my_dir/fix_scini_problems.sh

m1=$(juju add-machine --constraints "instance-type=i2.xlarge" 2>&1 | awk '{print $3}')
echo "Machine created: $m1"
m2=$(juju add-machine --constraints "instance-type=i2.xlarge" 2>&1 | awk '{print $3}')
echo "Machine created: $m2"
m3=$(juju add-machine --constraints "instance-type=i2.xlarge" 2>&1 | awk '{print $3}')
echo "Machine created: $m3"
m4=$(juju add-machine --constraints "instance-type=i2.xlarge" 2>&1 | awk '{print $3}')
echo "Machine created: $m4"
m5=$(juju add-machine --constraints "instance-type=i2.xlarge" 2>&1 | awk '{print $3}')
echo "Machine created: $m5"

trap catch_errors ERR

function save_logs() {
  # save status to file
  for mch in $m3 $m4 $m5 ; do
    mdir="$cdir/logs/$mch"
    mkdir -p "$mdir"
    juju ssh $mch 'cat /var/log/puppet-scaleio.log' > "$mdir/puppet-scaleio.log" 2>/dev/null
    juju ssh $mch 'cat /var/lib/hiera/defaults.yaml' > "$mdir/var-lib-hiera-defaults.log" 2>/dev/null
  done
}

function catch_errors() {
  local exit_code=$?
  save_logs
  exit $exit_code
}

echo "Wait for machines"
for mch in $m1 $m2 $m3 $m4 $m5 ; do
  iter=0
  while ! juju status | grep "\"$mch\"" &>/dev/null ; do
    echo "Waiting for machine $mch - $iter/12"
    if ((iter >= 12)); then
      echo "ERROR: Machine $mch didn't up."
      juju status
      exit 1
    fi
    ((++iter))
    sleep 10
  done
done
echo "Post-Wait for machines for 30 seconds"
sleep 30

juju deploy local:trusty/fuel-master --to 0
juju set fuel-master device-paths=/dev/xvdb

juju deploy local:trusty/fuel-node fuel-primary-controller --to $m3
juju set fuel-primary-controller roles="primary-controller cinder"

juju deploy local:trusty/fuel-node fuel-controller --to $m4
juju service add-unit fuel-controller --to $m5
juju set fuel-controller roles="controller cinder"

juju deploy local:trusty/fuel-node fuel-compute --to $m1
juju service add-unit fuel-compute --to $m2
juju set fuel-compute roles="compute"

juju add-relation fuel-master fuel-primary-controller
juju add-relation fuel-master fuel-controller
juju add-relation fuel-master fuel-compute
sleep 15

echo "Wait for services start: $(date)"
wait_absence_status_for_services "executing|blocked|waiting|allocating"
echo "Wait for services end: $(date)"

juju set fuel-master deploy=1
sleep 30

echo "Wait for services start: $(date)"
wait_absence_status_for_services "maintenance"
echo "Wait for services end: $(date)"

# check query_cluster output before exit on error if exists
master_mdm=`get_master_mdm "echo $m3 $m4 $m5"`
echo "INFO: query cluster on machine $mch"
juju ssh $master_mdm 'scli --query_cluster --approve_certificate'

# check for errors
if juju status | grep "current" | grep error ; then
  echo "ERROR: Some services went to error state"
  juju ssh 0 sudo grep Error /var/log/juju/all-machines.log 2>/dev/null
  exit 1
fi

for mch in $m1 $m2 $m3 $m4 $m5 ; do
  echo "INFO: check nova and cinder packages on machine $mch"
  juju ssh $mch 'dpkg -l | grep -P "nova|cinder"'
done

save_logs
