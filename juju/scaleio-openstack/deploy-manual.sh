#!/bin/bash -e

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

source $my_dir/../functions

juju deploy juju-gui --to 0
juju expose juju-gui
juju status

cd juju-scaleio

m1=$(juju add-machine --constraints "instance-type=r3.large" 2>&1 | awk '{print $3}')
echo "Machine created: $m1"
m2=$(juju add-machine --constraints "instance-type=r3.large" 2>&1 | awk '{print $3}')
echo "Machine created: $m2"
m3=$(juju add-machine --constraints "instance-type=i2.xlarge" 2>&1 | awk '{print $3}')
echo "Machine created: $m3"
m4=$(juju add-machine --constraints "instance-type=i2.xlarge" 2>&1 | awk '{print $3}')
echo "Machine created: $m4"
m5=$(juju add-machine --constraints "instance-type=i2.xlarge" 2>&1 | awk '{print $3}')
echo "Machine created: $m5"

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

echo "Deploy cinder"
juju deploy local:trusty/cinder --to $m1
juju set cinder "block-device=None" "debug=true" "glance-api-version=2" "openstack-origin=cloud:trusty-liberty" "overwrite=true"
juju expose cinder

echo "Deploy nova-api"
juju deploy cs:trusty/nova-cloud-controller --to $m5
juju set nova-cloud-controller "console-access-protocol=novnc" "debug=true" "openstack-origin=cloud:trusty-liberty"
juju expose nova-cloud-controller

echo "Deploy nova-compute"
juju deploy local:trusty/nova-compute --to $m1
juju service add-unit nova-compute --to $m2
juju set nova-compute "debug=true" "openstack-origin=cloud:trusty-liberty" "virt-type=qemu" "enable-resize=True" "enable-live-migration=True" "migration-auth-type=ssh" "libvirt-image-backend=sio"

echo "Deploy glance"
juju deploy cs:trusty/glance --to $m3
juju set glance "debug=true" "openstack-origin=cloud:trusty-liberty"
juju expose glance

echo "Deploy keystone"
juju deploy local:trusty/keystone --to $m4
juju set keystone "admin-password=password" "debug=true" "openstack-origin=cloud:trusty-liberty"
juju expose keystone

echo "Deploy rabbit mq"
juju deploy cs:trusty/rabbitmq-server --to $m2
juju set rabbitmq-server "source=cloud:trusty-liberty"

echo "Deploy mysql"
juju deploy cs:trusty/mysql --to $m2

echo "Deploy SDC"
juju deploy local:trusty/scaleio-sdc --to $m1
juju service add-unit scaleio-sdc --to $m2

echo "Deploy subordinate to OpenStack"
juju deploy local:trusty/scaleio-openstack

echo "Deploy gateway"
juju deploy local:trusty/scaleio-gw --to $m2

echo "Deploy MDM"
juju deploy local:trusty/scaleio-mdm --to $m3
juju set scaleio-mdm "cluster-mode=3"
juju service add-unit scaleio-mdm --to $m4
juju service add-unit scaleio-mdm --to $m5

echo "Deploy SDS"
juju deploy local:trusty/scaleio-sds --to $m3
juju service add-unit scaleio-sds --to $m4
juju service add-unit scaleio-sds --to $m5
juju set scaleio-sds "device-paths=/dev/xvdb"


echo "Add relations"
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


echo "Wait for services start: $(date)"
wait_absence_status_for_services "executing|blocked|waiting|allocating"
echo "Wait for services end: $(date)"

# check for errors
if juju status | grep "current" | grep error ; then
  echo "ERROR: Some services went to error state"
  juju ssh 0 sudo grep Error /var/log/juju/all-machines.log 2>/dev/null
  exit 1
fi

echo "Waiting for all services up"
sleep 60
