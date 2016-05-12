#!/bin/bash -e

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

source $my_dir/../functions
source $my_dir/functions

cd juju-scaleio

m1=$(juju add-machine --constraints "instance-type=r3.large" 2>&1 | awk '{print $3}')
echo "Machine created: $m1"
m2=$(juju add-machine --constraints "instance-type=i2.xlarge" 2>&1 | awk '{print $3}')
echo "Machine created: $m2"
m3=$(juju add-machine --constraints "instance-type=i2.xlarge" 2>&1 | awk '{print $3}')
echo "Machine created: $m3"
m4=$(juju add-machine --constraints "instance-type=i2.xlarge" 2>&1 | awk '{print $3}')
echo "Machine created: $m4"

wait_for_machines $m1 $m2 $m3 $m4

echo "Deploy cinder"
juju deploy cs:trusty/cinder --to $m1
juju set cinder "block-device=None" "debug=true" "glance-api-version=2" "openstack-origin=cloud:trusty-liberty" "overwrite=true"
juju expose cinder

echo "Deploy keystone"
juju deploy cs:trusty/keystone --to $m3
juju set keystone "admin-password=password" "debug=true" "openstack-origin=cloud:trusty-liberty"
juju expose keystone

echo "Deploy rabbit mq"
juju deploy cs:trusty/rabbitmq-server --to $m4
juju set rabbitmq-server "source=cloud:trusty-liberty"

echo "Deploy mysql"
juju deploy cs:trusty/mysql --to $m4

echo "Deploy SDC"
juju deploy local:trusty/scaleio-sdc --to $m1

echo "Deploy subordinate to OpenStack"
juju deploy local:trusty/scaleio-openstack

echo "Deploy gateway"
juju deploy local:trusty/scaleio-gw --to $m2
juju service add-unit scaleio-gw --to $m4

echo "Deploy MDM"
juju deploy local:trusty/scaleio-mdm --to $m2
juju set scaleio-mdm "cluster-mode=3"
juju service add-unit scaleio-mdm --to $m3
juju service add-unit scaleio-mdm --to $m4

echo "Deploy SDS"
juju deploy local:trusty/scaleio-sds --to $m2
juju service add-unit scaleio-sds --to $m3
juju service add-unit scaleio-sds --to $m4
juju set scaleio-sds "device-paths=/dev/xvdb"

echo "Set haproxy"
i=0
for ip_address in `juju status scaleio-gw | grep public-address | awk '{print $2}'` ; do
  ip_addresses[$i]=$ip_address
  ((++i))
done

juju set scaleio-gw "vip=${ip_addresses[0]}"

echo "Add relations"
juju add-relation "scaleio-sdc:scaleio-mdm" "scaleio-mdm:scaleio-mdm"
juju add-relation "keystone:shared-db" "mysql:shared-db"
juju add-relation "cinder:shared-db" "mysql:shared-db"
juju add-relation "cinder:amqp" "rabbitmq-server:amqp"
juju add-relation "cinder:identity-service" "keystone:identity-service"
juju add-relation "scaleio-sds:scaleio-sds" "scaleio-mdm:scaleio-sds"
juju add-relation "scaleio-gw:scaleio-mdm" "scaleio-mdm:scaleio-mdm"
juju add-relation "scaleio-openstack:scaleio-gw" "scaleio-gw:scaleio-gw"
juju add-relation "cinder:storage-backend" "scaleio-openstack:storage-backend"

sleep 30

juju status

echo "Wait for services start: $(date)"
wait_absence_status_for_services "executing|blocked|waiting|allocating"
echo "Wait for services end: $(date)"

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

master_mdm=`get_master_mdm`
echo "Master MDM found at $master_mdm"

# check installed cloud
auth_ip=`juju status keystone/0 --format json | jq .services.keystone.units | grep public-address | sed 's/[\",]//g' | awk '{print $2}'`
rm -rf .venv
virtualenv .venv
source .venv/bin/activate
pip install -q python-openstackclient

export OS_AUTH_URL=http://$auth_ip:5000/v2.0
export OS_USERNAME=admin
export OS_TENANT_NAME=admin
export OS_PROJECT_NAME=admin
export OS_PASSWORD=password

keystone catalog

echo "Check ScaleIO geteway IP setting in cinder.conf"
conf_ip=`juju ssh 1 sudo cat /etc/cinder/cinder.conf 2>/dev/null | grep san_ip | awk '{print $3}' | sed "s/\r//"`
if [[ "$conf_ip" != "${ip_addresses[0]}" ]] ; then
  echo "Error in ScaleIO geteway IP setting in cinder.conf"
  exit 1
fi
echo "Success"

echo "------------------------------  Check creation of cinder volumes"
cinder create --display_name simple_volume 1
if ! volume_id=`cinder list | grep " simple_volume " | awk '{print $2}'` ; then
  echo "No volume was created"
  exit 1
fi
wait_volume $volume_id

cinder list

cinder delete $volume_id >/dev/null

echo SUCCESS

# 4. Shut down $m2

# 5. Check

# 6. Raise $m2

# 7. Shut down $m4

# 8. Check

# 9. service scaleio-gw1 stop

# 10. service scaleio-ha2 stop

# 11. Check
