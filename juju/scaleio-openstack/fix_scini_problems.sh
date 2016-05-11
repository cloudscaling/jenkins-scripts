#!/bin/bash -ex

# check kernel
rm -f index.html
wget -nv "--ftp-user=QNzgdxXix" "--ftp-password=Aw3wFAwAq3" ftp://ftp.emc.com/Ubuntu/2.0.5014.0/
kernel=`juju ssh 0 'uname -r' 2>/dev/null`
if cat index.html | grep $kernel ; then
  echo "INFO: driver for kernel $kernel found on ftp.emc.com"
  exit
fi
echo "WARNING: driver for kernel $kernel not found on ftp.emc.com. Upgrade kernel to 4.2.0-30"

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
    juju ssh $machine uname -r 2>/dev/null
  done
}

# wait
wait_for_machines
# change kernel and reboot
for machine in $machine1 $machine2 ; do
  juju ssh $machine "sudo apt-get install -fqy linux-image-4.2.0-30-generic linux-headers-4.2.0-30-generic" 2>/dev/null
  juju ssh $machine "sudo reboot" 2>/dev/null
done
# wait
wait_for_machines

# change machine name in bundle to numbers
sed -i -e "s/\"compute-1\"/\"$machine1\"/m" $BUNDLE
sed -i -e "s/\"compute-2\"/\"$machine2\"/m" $BUNDLE
