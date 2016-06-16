#!/bin/bash -e

# all this file is an ugly hack

m1=$1
m2=$2

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

source $my_dir/../functions

# check kernel
rm -f index.html
wget -nv "--ftp-user=QNzgdxXix" "--ftp-password=Aw3wFAwAq3" ftp://ftp.emc.com/Ubuntu/2.0.5014.0/
kernel=`juju ssh 0 "uname -r" 2>/dev/null`
kernel=`echo $kernel | sed 's/\r//'`
if cat index.html | grep $kernel ; then
  echo "INFO: driver for kernel $kernel found on ftp.emc.com"
  exit
fi
echo "WARNING: driver for kernel $kernel not found on ftp.emc.com. Upgrade kernel to 4.2.0-30"

# due to problems with 'scini' driver we will update the kernel

created=0
if [[ -z "$m1" && -z "$m2" ]] ; then
  m1=$(create_machine 1 0)
  echo "Machine created: $m1"
  m2=$(create_machine 1 0)
  echo "Machine created: $m2"
  # wait
  wait_for_machines $m1 $m2
  created=1
fi

# change kernel and reboot
for machine in $m1 $m2 ; do
  juju ssh $machine "sudo apt-get install -fqy linux-image-4.2.0-30-generic linux-headers-4.2.0-30-generic" 2>/dev/null
  juju ssh $machine "sudo reboot" 2>/dev/null
done
# wait
wait_for_machines $m1 $m2

if [[ $created == '1' ]] ; then
  # change machine name in bundle to numbers
  # TODO: remove this from here
  sed -i -e "s/\"compute-1\"/\"$m1\"/m" $BUNDLE
  sed -i -e "s/\"compute-2\"/\"$m2\"/m" $BUNDLE
fi
