#!/bin/bash -ex

# due to problems with 'scini' driver we will run two machines and update kernel
juju machine add --constraints "instance-type=r3.large" -n 2

# TODO: get machine numbers
machine1=1
machine2=2

function wait_for_machines() {
  # wait for machines
  sleep 30
  for machine in $machine1 $machine2 ; do
    local fail=0
    while ! juju ssh $machine sudo apt-get install -fy joe &>/dev/null
    do
      if ((fail >= 12)); then
        echo "ERROR: Machine $machine did not up."
        exit 1
      fi
      sleep 10
      ((++fail))
    done
    juju ssh $machine uname -r
  done
}

# wait
wait_for_machines
# change kernel and reboot
for machine in $machine1 $machine2 ; do
  juju ssh $machine "sudo apt-get install -fqy linux-image-4.2.0-30-generic linux-headers-4.2.0-30-generic"
  juju ssh $machine "sudo reboot"
done
# wait
wait_for_machines

# change machine name in bundle to numbers
sed -i -e "s/\"compute-1\"/\"$machine1\"/m" $BUNDLE
sed -i -e "s/\"compute-2\"/\"$machine2\"/m" $BUNDLE
