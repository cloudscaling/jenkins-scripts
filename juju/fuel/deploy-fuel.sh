#!/bin/bash -e

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

source $my_dir/../functions
source $my_dir/../scaleio/static-checks

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
    juju ssh $mch 'cat /var/log/fuel-plugin-scaleio.log' > "$mdir/var_log_fuel-plugin-scaleio.log" 2>/dev/null
    juju ssh $mch 'cat /var/lib/hiera/defaults.yaml' > "$mdir/var_lib_hiera_defaults.log" 2>/dev/null
  done
}

function catch_errors() {
  local exit_code=$?
  save_logs
  exit $exit_code
}

# wait for machines up
wait_for_machines $m1 $m2 $m3 $m4 $m5

# check kernel at one machine
rm -f index.html
wget -nv "--ftp-user=QNzgdxXix" "--ftp-password=Aw3wFAwAq3" ftp://ftp.emc.com/Ubuntu/2.0.5014.0/
kernel=`juju ssh $m1 "uname -r" 2>/dev/null`
kernel=`echo $kernel | sed 's/\r//'`
if ! cat index.html | grep $kernel ; then
  echo "WARNING: driver for kernel $kernel not found on ftp.emc.com. Upgrade kernel to 4.2.0-30"

  # change kernel and reboot
  for machine in $m1 $m2 $m3 $m4 $m5 ; do
    echo "--- Updating machine $machine"
    juju ssh $machine "sudo apt-get install -fy linux-image-4.2.0-30-generic linux-headers-4.2.0-30-generic &>/dev/null" 2>/dev/null
    juju ssh $machine "sudo reboot" 2>/dev/null
  done

  # wait for machines up
  wait_for_machines $m1 $m2 $m3 $m4 $m5
fi
rm -f index.html


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
echo "INFO: query cluster on machine $master_mdm"
juju ssh $master_mdm 'scli --query_cluster --approve_certificate' 2>/dev/null

# check for errors
if juju status | grep "current" | grep error ; then
  echo "ERROR: Some services went to error state"
  juju ssh 0 sudo grep Error /var/log/juju/all-machines.log 2>/dev/null
  exit 1
fi

check-cluster "juju ssh" $master_mdm 3

save_logs
