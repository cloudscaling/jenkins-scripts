#!/bin/bash -ex

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

source $my_dir/../functions
source $my_dir/../scaleio/static-checks

export USERNAME='admin'
export PASSWORD="Default_password"

echo "INFO: start $(date)"

echo "Create machines"
m1=$(juju add-machine --constraints "instance-type=r3.large" 2>&1 | awk '{print $3}')
echo "Machine created: $m1"
m2=$(juju add-machine --constraints "instance-type=t2.medium" 2>&1 | awk '{print $3}')
echo "Machine created: $m2"
m3=$(juju add-machine --constraints "$INSTANCE_TYPE" 2>&1 | awk '{print $3}')
echo "Machine created: $m3"
#m4=$(juju add-machine --constraints "$INSTANCE_TYPE" 2>&1 | awk '{print $3}')
#echo "Machine created: $m4"
#m5=$(juju add-machine --constraints "$INSTANCE_TYPE" 2>&1 | awk '{print $3}')
#echo "Machine created: $m5"

wait_for_machines $m1 $m2 $m3 #$m4 $m5

instances=`juju status | grep instance-id | awk '{print$2}'`

i=0
for instance in $instances ; do
  if [[ $i != 0 ]] ; then
    create_attach_volume $instance 100 "/dev/xvdf"
    create_attach_volume $instance 100 "/dev/xvdg"
  fi
  ((++i))
done

# deploy fake charms to prevent machines removing
juju deploy ubuntu --to $m1
juju service add-unit ubuntu --to $m2
juju service add-unit ubuntu --to $m3
#juju service add-unit ubuntu --to $m4
#juju service add-unit ubuntu --to $m5

errors=0

function run-test() {
  echo "INFO: $1 $(date)"
  $@ || (( ++errors ))
}

run-test "$my_dir"/__check-capacity-alerts.sh
run-test "$my_dir"/__check-mdm-password.sh
run-test "$my_dir"/__check-protection-domains.sh $m1 $m2
run-test "$my_dir"/__check-storage-pool-parameters.sh $m1 $m2
run-test "$my_dir"/__check-cache-parameters.sh $m1 $m2 $m3

exit $errors
