#!/bin/bash -e

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

rm -f errors
touch errors
export MAX_FAIL=30

source $my_dir/../functions
source $my_dir/../functions-openstack

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
juju deploy local:trusty/cinder --to $m1
juju set cinder "block-device=None" "debug=true" "glance-api-version=2" "openstack-origin=cloud:trusty-liberty" "overwrite=true"
juju expose cinder

echo "Deploy keystone"
juju deploy local:trusty/keystone --to $m3
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
juju expose scaleio-gw

echo "Deploy MDM"
juju deploy local:trusty/scaleio-mdm --to $m2

echo "Deploy SDS"
juju deploy local:trusty/scaleio-sds --to $m2
juju service add-unit scaleio-sds --to $m3
juju service add-unit scaleio-sds --to $m4
juju set scaleio-sds "device-paths=/dev/xvdb"

cd ..

sleep 10
ip_addresses=(`juju status scaleio-gw | grep public-address | awk '{print $2}'`)
echo "Configure haproxy"
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

# check installed cloud
rm -rf .venv
virtualenv .venv
source .venv/bin/activate
pip install -q python-openstackclient

auth_ip=`juju status keystone/0 --format json | jq .services.keystone.units | grep public-address | sed 's/[\",]//g' | awk '{print $2}'`
export OS_AUTH_URL=http://$auth_ip:5000/v2.0
export OS_USERNAME=admin
export OS_TENANT_NAME=admin
export OS_PROJECT_NAME=admin
export OS_PASSWORD=password

keystone catalog

function check_volume_creation() {
  local volume_name=simple_volume_$1

  volume_id=`cinder create --display_name $volume_name 1 | grep " id " | awk '{print $4}'`
  echo "INFO: Volume created. Name: $volume_name  Id: $volume_id"
  wait_volume $volume_id

  status=`cinder show $volume_id | awk '/ status / {print $4}'`
  if [[ $status == "available" ]]; then
    echo "INFO: Success"
  elif [[ $status == "error" || -z "$status" ]]; then
    echo 'ERROR: Volume creation error'
  fi
  if ! output=`cinder delete $volume_id` ; then
    echo "$output" >> errors
    echo 'ERROR: Volume deletion error'
  fi
}

function check_cinder_conf() {
  gw_ip=$1
  echo "INFO: Check ScaleIO gateway IP setting in cinder.conf"
  conf_ip=`juju ssh 1 sudo cat /etc/cinder/cinder.conf 2>/dev/null | grep san_ip | awk '{print $3}' | sed "s/\r//"`
  if [[ "$conf_ip" != "$gw_ip" ]] ; then
    echo "ERROR: Error in ScaleIO gateway IP setting in cinder.conf"
    echo "ERROR: Expected $gw_ip, but got $conf_ip"
    return 1
  fi
  echo "INFO: Success"
}

function check_haproxy_responses() {
  gw_ip1=$1
  gw_ip2=$2
  resp=`curl -k -u admin:Default_password https://$gw_ip1:4443/api/login 2>/dev/null`
  echo "INFO: Check server HA1($gw_ip1) response: $resp"
  resp=`curl -k -u admin:Default_password https://$gw_ip2:4443/api/login 2>/dev/null`
  echo "INFO: Check server HA2($gw_ip2) response: $resp"
}

trap catch_errors ERR

function catch_errors() {
  local exit_code=$?
  echo "ERROR: error catched: " $exit_code $@

  $my_dir/save_logs.sh
  exit $exit_code
}

check_cinder_conf ${ip_addresses[0]}

check_haproxy_responses ${ip_addresses[@]}
echo "INFO: Check creation of cinder volume through gw1 $(date)"
check_volume_creation ha1_gw1

echo "INFO: Stop scaleio-gateway service on the first gateway $(date)"
juju ssh 2 'sudo service scaleio-gateway stop || /bin/true' 2>/dev/null
sleep 10
echo "INFO: Check status scaleio-gateway service on the first gateway $(date)"
juju ssh 2 sudo service scaleio-gateway status 2>/dev/null

check_haproxy_responses ${ip_addresses[@]}
echo "INFO: Check creation of cinder volume through gw2 $(date)"
check_volume_creation ha1_gw2

echo "INFO: Configure haproxy to second GW $(date)"
juju set scaleio-gw "vip=${ip_addresses[1]}"
sleep 30
echo "INFO: Wait for services start: $(date)"
wait_absence_status_for_services "executing|blocked|waiting|allocating"
echo "INFO: Wait for services end: $(date)"

check_cinder_conf ${ip_addresses[1]}

check_haproxy_responses ${ip_addresses[@]}
echo "INFO: Check creation of cinder volume through gw2 $(date)"
check_volume_creation ha2_gw2

echo "INFO: Start scaleio-gateway service on the first gateway $(date)"
juju ssh 2 'sudo service scaleio-gateway start || /bin/true' 2>/dev/null
sleep 10
echo "INFO: Check status scaleio-gateway service on the first gateway $(date)"
juju ssh 2 sudo service scaleio-gateway status 2>/dev/null
echo "INFO: Stop scaleio-gateway service on the second gateway $(date)"
juju ssh 4 'sudo service scaleio-gateway stop || /bin/true' 2>/dev/null
sleep 10
echo "INFO: Check status scaleio-gateway service on the second gateway $(date)"
juju ssh 4 sudo service scaleio-gateway status 2>/dev/null

check_haproxy_responses ${ip_addresses[@]}
echo "INFO: Check creation of cinder volume through gw1 $(date)"
check_volume_creation ha2_gw1

trap - ERR

$my_dir/../scaleio-openstack/save_logs.sh

if [ -s errors ] ; then
  cat errors
  exit 1
fi

echo "SUCCESS"
