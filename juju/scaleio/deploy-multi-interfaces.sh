#!/bin/bash -eu

# it deploys 3 machines of type i2.xlarge and attaches four interfaces to each

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

source $my_dir/../functions
source $my_dir/../scaleio/static-checks

export USERNAME='admin'
export PASSWORD="Default_password"

echo "INFO: start $(date)"

# hard-coded in account of Pavlov Andrey. (already created)
# TODO: rework it
subnet0="subnet-6e0d0407"
subnet1="subnet-740d041d"
subnet2="subnet-5b0d0432"
subnet3="subnet-2c0d0445"

# do not fail if they already exist (for second run)
# in fact only net0 is needed
juju space create net0 || /bin/true
juju subnet add 172.31.100.0/24 net0 || /bin/true
juju space create net1 || /bin/true
juju subnet add 172.31.101.0/24 net1 || /bin/true
juju space create net2 || /bin/true
juju subnet add 172.31.102.0/24 net2 || /bin/true
juju space create net3 || /bin/true
juju subnet add 172.31.103.0/24 net3 || /bin/true

m1=$(create_machine 0 0 "spaces=net0")
echo "Machine created: $m1"
m2=$(create_machine 0 0 "spaces=net0")
echo "Machine created: $m2"
m3=$(create_machine 0 0 "spaces=net0")
echo "Machine created: $m3"

wait_for_machines $m1 $m2 $m3

# deploy fake charms to prevent machines removing
juju-deploy ubuntu --to $m1
juju-add-unit ubuntu --to $m2
juju-add-unit ubuntu --to $m3

eni01=`aws ec2 create-network-interface --subnet-id $subnet1 | grep '"NetworkInterfaceId":' | sed 's/.*"\(eni-[0-9a-f]*\)",/\1/'`
eni02=`aws ec2 create-network-interface --subnet-id $subnet2 | grep '"NetworkInterfaceId":' | sed 's/.*"\(eni-[0-9a-f]*\)",/\1/'`
eni03=`aws ec2 create-network-interface --subnet-id $subnet3 | grep '"NetworkInterfaceId":' | sed 's/.*"\(eni-[0-9a-f]*\)",/\1/'`

eni11=`aws ec2 create-network-interface --subnet-id $subnet1 | grep '"NetworkInterfaceId":' | sed 's/.*"\(eni-[0-9a-f]*\)",/\1/'`
eni12=`aws ec2 create-network-interface --subnet-id $subnet2 | grep '"NetworkInterfaceId":' | sed 's/.*"\(eni-[0-9a-f]*\)",/\1/'`
eni13=`aws ec2 create-network-interface --subnet-id $subnet3 | grep '"NetworkInterfaceId":' | sed 's/.*"\(eni-[0-9a-f]*\)",/\1/'`

eni21=`aws ec2 create-network-interface --subnet-id $subnet1 | grep '"NetworkInterfaceId":' | sed 's/.*"\(eni-[0-9a-f]*\)",/\1/'`
eni22=`aws ec2 create-network-interface --subnet-id $subnet2 | grep '"NetworkInterfaceId":' | sed 's/.*"\(eni-[0-9a-f]*\)",/\1/'`
eni23=`aws ec2 create-network-interface --subnet-id $subnet3 | grep '"NetworkInterfaceId":' | sed 's/.*"\(eni-[0-9a-f]*\)",/\1/'`

ec2m1=`juju-status-tabular | grep -A 10 '\[Machines\]' | grep "^$m1 .*" | awk '{print $5}'`
ec2m2=`juju-status-tabular | grep -A 10 '\[Machines\]' | grep "^$m2 .*" | awk '{print $5}'`
ec2m3=`juju-status-tabular | grep -A 10 '\[Machines\]' | grep "^$m3 .*" | awk '{print $5}'`

id=`aws ec2 attach-network-interface --network-interface-id $eni01 --instance-id $ec2m1 --device-index 1 | grep '"AttachmentId":' | sed 's/.*"\(eni-attach-[0-9a-f]*\)"/\1/'`
aws ec2 modify-network-interface-attribute --network-interface-id $eni01 --attachment AttachmentId=$id,DeleteOnTermination=true
id=`aws ec2 attach-network-interface --network-interface-id $eni02 --instance-id $ec2m1 --device-index 2 | grep '"AttachmentId":' | sed 's/.*"\(eni-attach-[0-9a-f]*\)"/\1/'`
aws ec2 modify-network-interface-attribute --network-interface-id $eni02 --attachment AttachmentId=$id,DeleteOnTermination=true
id=`aws ec2 attach-network-interface --network-interface-id $eni03 --instance-id $ec2m1 --device-index 3 | grep '"AttachmentId":' | sed 's/.*"\(eni-attach-[0-9a-f]*\)"/\1/'`
aws ec2 modify-network-interface-attribute --network-interface-id $eni03 --attachment AttachmentId=$id,DeleteOnTermination=true

id=`aws ec2 attach-network-interface --network-interface-id $eni11 --instance-id $ec2m2 --device-index 1 | grep '"AttachmentId":' | sed 's/.*"\(eni-attach-[0-9a-f]*\)"/\1/'`
aws ec2 modify-network-interface-attribute --network-interface-id $eni11 --attachment AttachmentId=$id,DeleteOnTermination=true
id=`aws ec2 attach-network-interface --network-interface-id $eni12 --instance-id $ec2m2 --device-index 2 | grep '"AttachmentId":' | sed 's/.*"\(eni-attach-[0-9a-f]*\)"/\1/'`
aws ec2 modify-network-interface-attribute --network-interface-id $eni12 --attachment AttachmentId=$id,DeleteOnTermination=true
id=`aws ec2 attach-network-interface --network-interface-id $eni13 --instance-id $ec2m2 --device-index 3 | grep '"AttachmentId":' | sed 's/.*"\(eni-attach-[0-9a-f]*\)"/\1/'`
aws ec2 modify-network-interface-attribute --network-interface-id $eni13 --attachment AttachmentId=$id,DeleteOnTermination=true

id=`aws ec2 attach-network-interface --network-interface-id $eni21 --instance-id $ec2m3 --device-index 1 | grep '"AttachmentId":' | sed 's/.*"\(eni-attach-[0-9a-f]*\)"/\1/'`
aws ec2 modify-network-interface-attribute --network-interface-id $eni21 --attachment AttachmentId=$id,DeleteOnTermination=true
id=`aws ec2 attach-network-interface --network-interface-id $eni22 --instance-id $ec2m3 --device-index 2 | grep '"AttachmentId":' | sed 's/.*"\(eni-attach-[0-9a-f]*\)"/\1/'`
aws ec2 modify-network-interface-attribute --network-interface-id $eni22 --attachment AttachmentId=$id,DeleteOnTermination=true
id=`aws ec2 attach-network-interface --network-interface-id $eni23 --instance-id $ec2m3 --device-index 3 | grep '"AttachmentId":' | sed 's/.*"\(eni-attach-[0-9a-f]*\)"/\1/'`
aws ec2 modify-network-interface-attribute --network-interface-id $eni23 --attachment AttachmentId=$id,DeleteOnTermination=true

for mm in $m1 $m2 $m3 ; do
  for ii in 1 2 3 ; do 
    juju-ssh $mm "sudo bash -c 'echo \"auto eth$ii\" > /etc/network/interfaces.d/eth$ii.cfg && echo \"iface eth$ii inet dhcp\" >> /etc/network/interfaces.d/eth$ii.cfg && ifup eth$ii'" 2>/dev/null
  done
  juju-ssh $mm ip addr 2>/dev/null
done
