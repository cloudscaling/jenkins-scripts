#!/bin/bash -e

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

source $my_dir/../functions

juju deploy juju-gui --to 0
juju expose juju-gui
juju status

cd juju-scaleio

# this script will change current bundle and it must be called here...
#$my_dir/fix_scini_problems.sh

m1=$(juju add-machine --constraints "instance-type=r3.large" | awk '{print $3}')
echo "Machine create: $m1"
m2=$(juju add-machine --constraints "instance-type=r3.large" | awk '{print $3}')
echo "Machine create: $m2"
m3=$(juju add-machine --constraints "instance-type=i2.xlarge" | awk '{print $3}')
echo "Machine create: $m3"
m4=$(juju add-machine --constraints "instance-type=i2.xlarge" | awk '{print $3}')
echo "Machine create: $m4"
m5=$(juju add-machine --constraints "instance-type=i2.xlarge" | awk '{print $3}')
echo "Machine create: $m5"

juju deploy cs:trusty/cinder --to $m1
juju set cinder "block-device=None" "debug=true" "glance-api-version=2" "openstack-origin=cloud:trusty-kilo" "overwrite=true"
juju expose cinder

juju deploy cs:trusty/nova-cloud-controller --to $m5
juju set nova-cloud-controller "console-access-protocol=novnc" "debug=true" "openstack-origin=cloud:trusty-kilo"
juju expose nova-cloud-controller

juju deploy local:trusty/nova-compute --to $m1
juju service add-unit nova-compute --to $m2
juju set nova-compute "debug=true" "openstack-origin=cloud:trusty-kilo" "virt-type=qemu" "enable-resize=True" "enable-live-migration=True" "migration-auth-type=ssh" "libvirt-image-backend=sio"

juju deploy cs:trusty/glance --to $m3
juju set glance "debug=true" "openstack-origin=cloud:trusty-kilo"
juju expose glance

juju deploy cs:trusty/keystone --to $m4
juju set keystone "admin-password=password" "debug=true" "openstack-origin=cloud:trusty-kilo"
juju expose keystone

juju deploy cs:trusty/rabbitmq-server --to $m2
juju set rabbitmq-server "source=cloud:trusty-kilo"

juju deploy cs:trusty/mysql --to $m2


juju deploy local:trusty/scaleio-sdc --to $m1
juju service add-unit scaleio-sdc --to $m2

juju deploy local:trusty/scaleio-openstack

juju deploy local:trusty/scaleio-gw --to $m2

juju deploy local:trusty/scaleio-mdm --to $m3
juju service add-unit scaleio-mdm --to $m4
juju service add-unit scaleio-mdm --to $m5

juju deploy local:trusty/scaleio-sds --to $m3
juju service add-unit scaleio-sds --to $m4
juju service add-unit scaleio-sds --to $m5
juju set scaleio-sds "device-paths=/dev/xvdb"


juju add-relation "scaleio-sdc:scaleio-mdm" "scaleio-mdm:scaleio-mdm"
juju add-relation "nova-compute:shared-db" "mysql:shared-db"
juju add-relation "nova-cloud-controller:cinder-volume-service" "cinder:cinder-volume-service"
juju add-relation "keystone:shared-db" "mysql:shared-db"
juju add-relation "glance:shared-db" "mysql:shared-db"
juju add-relation "keystone:identity-service" "glance:identity-service"
juju add-relation "nova-cloud-controller:image-service" "glance:image-service"
juju add-relation "cinder:shared-db" "mysql:shared-db"
juju add-relation "cinder:amqp" "rabbitmq-server:amqp"
juju add-relation "cinder:identity-service" "keystone:identity-service"
juju add-relation "nova-cloud-controller:identity-service" "keystone:identity-service"
juju add-relation "scaleio-sds:scaleio-sds" "scaleio-mdm:scaleio-sds"
juju add-relation "nova-cloud-controller:cloud-compute" "nova-compute:cloud-compute"
juju add-relation "nova-compute:image-service" "glance:image-service"
juju add-relation "nova-compute:amqp" "rabbitmq-server:amqp"
juju add-relation "nova-cloud-controller:shared-db" "mysql:shared-db"
juju add-relation "scaleio-gw:scaleio-mdm" "scaleio-mdm:scaleio-mdm"
juju add-relation "nova-cloud-controller:amqp" "rabbitmq-server:amqp"
juju add-relation "cinder:image-service" "glance:image-service"
juju add-relation "scaleio-openstack:scaleio-gw" "scaleio-gw:scaleio-gw"
juju add-relation "cinder:storage-backend" "scaleio-openstack:storage-backend"
juju add-relation "nova-compute:ephemeral-backend" "scaleio-openstack:ephemeral-backend"


if ! err=$(wait_for_services "executing|blocked|waiting") ; then
  echo $err
  exit 1
fi

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
