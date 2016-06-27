#!/bin/bash -e

# input: list of machines to check and upgrade if needed

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

source $my_dir/../functions

function check_kernel() {
  local machine=$1

  kernel=`juju ssh $machine "uname -r" 2>/dev/null`
  kernel=`echo $kernel | sed 's/\r//'`

  rm -f index.html
  wget -t 2 -T 30 -nv "--ftp-user=QNzgdxXix" "--ftp-password=Aw3wFAwAq3" ftp://ftp.emc.com/Ubuntu/2.0.5014.0/
  if grep -q $kernel index.html ; then
    rm -f index.html
    wget -t 2 -T 30 -nv "--ftp-user=QNzgdxXix" "--ftp-password=Aw3wFAwAq3" ftp://ftp.emc.com/Ubuntu/2.0.5014.0/${kernel}/
    if grep -q 'scini.tar' index.html ; then
      rm -f index.html
      return 0
    fi
  fi
  rm -f index.html
  return 1
}

function upgrade_kernel() {
  local machine=$1

  juju ssh $machine "sudo apt-get install -fqy linux-image-4.2.0-30-generic linux-headers-4.2.0-30-generic" 2>/dev/null
  juju ssh $machine "sudo reboot" 2>/dev/null
}

for machine in $@ ; do
  echo "INFO: check machine $machine"
  if ! check_kernel $machine ; then
    echo "WARNING: driver for kernel $kernel not found on ftp.emc.com. Upgrade kernel to 4.2.0-30"
    upgrade_kernel $machine
  else
    echo "INFO: driver for kernel $kernel found on ftp.emc.com"
  fi
done

wait_for_machines $@
