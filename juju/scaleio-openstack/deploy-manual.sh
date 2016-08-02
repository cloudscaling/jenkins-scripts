#!/bin/bash -e

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

source $my_dir/../functions

deploy_from=${1:-github}   # Place where to get ScaleIO charms - github or charmstore

if [[ "$deploy_from" == github ]] ; then
  params="--repository juju-scaleio local:"
else
  # deploy_from=charmstore
  params="cs:~cloudscaling/"
fi

VERSION=${VERSION:-"cloud:trusty-liberty"}
echo "---------------------------------------------------- From: $deploy_from  Version: $VERSION"

juju deploy juju-gui --to 0
juju expose juju-gui
juju status --format tabular

m1=$(create_machine 1 0)
echo "INFO: Machine created: $m1"
m2=$(create_machine 1 0)
echo "INFO: Machine created: $m2"
m3=$(create_machine 2 1)
echo "INFO: Machine created: $m3"
m4=$(create_machine 2 1)
echo "INFO: Machine created: $m4"
m5=$(create_machine 2 1)
echo "INFO: Machine created: $m5"

wait_for_machines $m1 $m2 $m3 $m4 $m5
apply_developing_puppets $m1 $m2 $m3 $m4 $m5
fix_kernel_drivers $m1 $m2 $m3 $m4 $m5

create_eth1 $m1
create_eth1 $m2

echo "INFO: Deploy cinder"
juju deploy cs:cinder --to $m1
juju set cinder "block-device=None" "debug=true" "glance-api-version=2" "openstack-origin=$VERSION" "overwrite=true"
juju expose cinder

echo "INFO: Deploy nova-api"
juju deploy cs:nova-cloud-controller --to $m5
juju set nova-cloud-controller "console-access-protocol=novnc" "debug=true" "openstack-origin=$VERSION"
juju expose nova-cloud-controller

echo "INFO: Deploy nova-compute"
juju deploy cs:nova-compute --to $m1
juju service add-unit nova-compute --to $m2
juju set nova-compute "debug=true" "openstack-origin=$VERSION" "virt-type=qemu" "enable-resize=True" "enable-live-migration=True" "migration-auth-type=ssh" "libvirt-image-backend=sio"

echo "INFO: Deploy glance"
juju deploy cs:glance --to $m3
juju set glance "debug=true" "openstack-origin=$VERSION"
juju expose glance

echo "INFO: Deploy keystone"
juju deploy cs:keystone --to $m2
juju set keystone "admin-password=password" "debug=true" "openstack-origin=$VERSION"
juju expose keystone

echo "INFO: Deploy rabbit mq"
juju deploy cs:rabbitmq-server --to $m4
juju set rabbitmq-server "source=$VERSION"

echo "INFO: Deploy mysql"
juju deploy cs:mysql --to $m4

echo "INFO: Deploy SDC"
juju deploy ${params}scaleio-sdc --to $m1
juju service add-unit scaleio-sdc --to $m2

echo "INFO: Deploy subordinate to OpenStack"
juju deploy ${params}scaleio-openstack

echo "INFO: Deploy gateway"
juju deploy ${params}scaleio-gw --to $m4
juju expose scaleio-gw

echo "INFO: Deploy MDM"
juju deploy ${params}scaleio-mdm --to $m3
juju set scaleio-mdm "cluster-mode=3"
juju service add-unit scaleio-mdm --to $m4
juju service add-unit scaleio-mdm --to $m5

echo "INFO: Deploy SDS"
juju deploy ${params}scaleio-sds --to $m3
juju service add-unit scaleio-sds --to $m4
juju service add-unit scaleio-sds --to $m5
juju set scaleio-sds "device-paths=/dev/xvdf"


echo "INFO: Add relations"
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


echo "INFO: Wait for services start: $(date)"
wait_absence_status_for_services "executing|blocked|waiting|allocating"
echo "INFO: Wait for services end: $(date)"

# check for errors
if juju status | grep "current" | grep error ; then
  echo "ERROR: Some services went to error state"
  juju ssh 0 sudo grep Error /var/log/juju/all-machines.log 2>/dev/null
  exit 1
fi

echo "INFO: Waiting for all services up"
sleep 60
