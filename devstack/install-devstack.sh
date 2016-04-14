#!/bin/bash -e

localrcfile=$1
ENV_FILE="cloudrc"
SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ServerAliveInterval=30"

source $ENV_FILE
SSH_DEST="ubuntu@$public_ip"
SSH="ssh -i kp $SSH_OPTS $SSH_DEST"
SCP="scp -i kp $SSH_OPTS"

while [ $($SSH 'pwd > /dev/null' ; echo $?) != 0 ]; do
  sleep 5
done

echo -------------------------------------------------------------------------- $(date)
$SSH "sudo apt-get -qq update"
$SSH "sudo DEBIAN_FRONTEND=noninteractive apt-get -fqy -o Dpkg::Options::=\"--force-confnew\" upgrade"
$SSH "sudo reboot"

sleep 30
while [ $($SSH 'pwd > /dev/null' ; echo $?) != 0 ]; do
  sleep 5
done

echo -------------------------------------------------------------------------- $(date)
$SSH "(echo o; echo n; echo p; echo 1; echo ; echo ; echo w) | sudo fdisk /dev/xvdh"
$SSH "sudo mkfs.ext4 /dev/xvdh1"
$SSH "sudo mkdir -p /opt/stack"
$SSH "sudo su -c \"echo '/dev/xvdh1  /opt/stack  auto  defaults,auto  0  0' >> /etc/fstab\""
$SSH "sudo mount /opt/stack"
$SSH "sudo chown \$USER /opt/stack"

$SSH "sudo sed -i 's/# deb/deb/g' /etc/apt/sources.list"
$SSH "sudo apt-get -qq update"
$SSH "sudo DEBIAN_FRONTEND=noninteractive apt-get -fqy install git ebtables bridge-utils"
$SSH "git clone https://github.com/openstack-dev/devstack.git"

echo -------------------------------------------------------------------------- $(date)
cp $localrcfile localrc
sed -i "s\^SERVICE_HOST.*$\SERVICE_HOST=$public_ip\m" localrc
$SCP localrc $SSH_DEST:devstack/localrc
echo "Installing devstack"
$SSH "cd devstack; ./stack.sh < /dev/null > stack.log 2>&1"
exit_code=$?
if [[ $exit_code != 0 ]]; then
  $SSH "cat devstack/stack.log"
  exit $exit_code
fi
echo -------------------------------------------------------------------------- $(date)
