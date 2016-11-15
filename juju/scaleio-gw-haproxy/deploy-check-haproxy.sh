#!/bin/bash -e

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"
os_source="cloud:trusty-liberty"

rm -f errors
touch errors
export MAX_FAIL=30

source $my_dir/../functions
source $my_dir/../functions-openstack

m1=$(create_machine 1 0)
echo "Machine created: $m1"
m2=$(create_machine 0 1)
echo "Machine created: $m2"
m3=$(create_machine 2 1)
echo "Machine created: $m3"
m4=$(create_machine 2 1)
echo "Machine created: $m4"

wait_for_machines $m1 $m2 $m3 $m4
apply_developing_puppets $m1 $m2 $m3 $m4
fix_kernel_drivers $m1 $m2 $m3 $m4

echo "Deploy cinder"
juju-deploy cs:cinder --to $m1
juju-set cinder "block-device=None" "debug=true" "glance-api-version=2" "openstack-origin=$os_source" "overwrite=true"
juju-expose cinder

echo "Deploy keystone"
juju-deploy cs:keystone --to $m3
juju-set keystone "admin-password=password" "debug=true" "openstack-origin=$os_source"
juju-expose keystone

echo "Deploy rabbit mq"
juju-deploy cs:rabbitmq-server --to $m4
juju-set rabbitmq-server "source=$os_source"

echo "Deploy mysql"
juju-deploy cs:percona-cluster mysql --to $m4

echo "Deploy SDC"
juju-deploy --repository juju-scaleio local:scaleio-sdc --to $m1

echo "Deploy subordinate to OpenStack"
juju-deploy --repository juju-scaleio local:scaleio-openstack

echo "Deploy gateway"
juju-deploy --repository juju-scaleio local:scaleio-gw --to $m2
juju-add-unit scaleio-gw --to $m4
juju-expose scaleio-gw

echo "Deploy MDM"
juju-deploy --repository juju-scaleio local:scaleio-mdm --to $m2

echo "Deploy SDS"
juju-deploy --repository juju-scaleio local:scaleio-sds --to $m2
juju-add-unit scaleio-sds --to $m3
juju-add-unit scaleio-sds --to $m4
juju-set scaleio-sds "device-paths=/dev/xvdf"

sleep 10
ip_addresses=(`juju-status scaleio-gw | grep public-address | awk '{print $2}'`)
echo "Configure haproxy"
juju-set scaleio-gw "vip=${ip_addresses[0]}"

echo "Add relations"
juju-add-relation "scaleio-sdc:scaleio-mdm" "scaleio-mdm:scaleio-mdm"
juju-add-relation "keystone:shared-db" "mysql:shared-db"
juju-add-relation "cinder:shared-db" "mysql:shared-db"
juju-add-relation "cinder:amqp" "rabbitmq-server:amqp"
juju-add-relation "cinder:identity-service" "keystone:identity-service"
juju-add-relation "scaleio-sds:scaleio-sds" "scaleio-mdm:scaleio-sds"
juju-add-relation "scaleio-gw:scaleio-mdm" "scaleio-mdm:scaleio-mdm"
juju-add-relation "scaleio-openstack:scaleio-gw" "scaleio-gw:scaleio-gw"
juju-add-relation "cinder:storage-backend" "scaleio-openstack:storage-backend"

sleep 30

echo "Wait for services start: $(date)"
wait_absence_status_for_services "executing|blocked|waiting|allocating"
echo "Wait for services end: $(date)"

# check for errors
if juju-status | grep "current" | grep error ; then
  echo "ERROR: Some services went to error state"
  juju-ssh 0 sudo grep Error /var/log/juju/all-machines.log 2>/dev/null
  exit 1
fi

echo "Waiting for all services up"
sleep 60

create_stackrc
source $WORKSPACE/stackrc

# check installed cloud
create_virtualenv

source $WORKSPACE/.venv/bin/activate
openstack catalog list

function check_cinder_conf() {
  local gw_ip=$1
  echo "INFO: Check ScaleIO gateway IP setting in cinder.conf"
  local conf_ip=`juju-ssh 1 sudo cat /etc/cinder/cinder.conf 2>/dev/null | grep san_ip | awk '{print $3}' | sed "s/\r//"`
  if [[ "$conf_ip" != "$gw_ip" ]] ; then
    echo "ERROR: Error in ScaleIO gateway IP setting in cinder.conf"
    echo "ERROR: Expected $gw_ip, but got $conf_ip"
    return 1
  fi
  echo "INFO: Success"
}

function check_haproxy_responses() {
  local gw_ip1=$1
  local gw_ip2=$2
  local ret=0
  for gw_ip in $gw_ip1 $gw_ip2 ; do
    echo "INFO: Check server HA($gw_ip):"
    if ! resp=`curl -k -u admin:Default_password https://$gw_ip:4443/api/login 2>/dev/null` ; then
      echo "ERROR: Response: $resp"
      ((++ret))
    fi
    echo "INFO: Success. Response: $resp"
  done
  return $ret
}

function check_volume_creation() {
  local volume_name=simple_volume_$1

  if ! output=`cinder create --display_name $volume_name 1` ; then
    echo "ERROR: Volume creation error: $volume_name"
    echo "$output"
    return 1
  fi
  local volume_id=`echo "$output" | grep " id " | awk '{print $4}'`
  echo "INFO: Volume created. Name: $volume_name  Id: $volume_id"
  wait_volume $volume_id $MAX_FAIL

  local ret=0
  local status=`cinder show $volume_id | awk '/ status / {print $4}'`
  if [[ $status == "available" ]]; then
    echo "INFO: Volume successfully built."
  elif [[ $status == "error" || -z "$status" ]]; then
    echo 'ERROR: Volume was build with errors:'
    cinder show $volume_id
    ret=1
  fi
  cinder delete $volume_id 1>/dev/null
  return $ret
}

trap 'catch_errors $LINENO' ERR

function catch_errors() {
  local exit_code=$?
  echo "Line: $1  Error=$exit_code  Command: '$(eval echo $BASH_COMMAND)'"
  trap - ERR

  $my_dir/save_logs.sh
  exit $exit_code
}

ret=0

check_cinder_conf ${ip_addresses[0]}

check_haproxy_responses ${ip_addresses[@]}
echo "INFO: Check creation of cinder volume through gw1 $(date)"
check_volume_creation ha1_gw1 || ret=1

echo "INFO: Stop scaleio-gateway service on the first gateway $(date)"
juju-ssh 2 'sudo service scaleio-gateway stop || /bin/true' 2>/dev/null
sleep 10
echo "INFO: Check status scaleio-gateway service on the first gateway $(date)"
juju-ssh 2 sudo service scaleio-gateway status 2>/dev/null

check_haproxy_responses ${ip_addresses[@]}
echo "INFO: Check creation of cinder volume through gw2 $(date)"
check_volume_creation ha1_gw2 || ret=1

echo "INFO: Configure haproxy to second GW $(date)"
juju-set scaleio-gw "vip=${ip_addresses[1]}"
sleep 30
echo "INFO: Wait for services start: $(date)"
wait_absence_status_for_services "executing|blocked|waiting|allocating"
echo "INFO: Wait for services end: $(date)"

check_cinder_conf ${ip_addresses[1]}

check_haproxy_responses ${ip_addresses[@]}
echo "INFO: Check creation of cinder volume through gw2 $(date)"
check_volume_creation ha2_gw2 || ret=1

echo "INFO: Start scaleio-gateway service on the first gateway $(date)"
juju-ssh 2 'sudo service scaleio-gateway start || /bin/true' 2>/dev/null
sleep 10
echo "INFO: Check status scaleio-gateway service on the first gateway $(date)"
juju-ssh 2 sudo service scaleio-gateway status 2>/dev/null
echo "INFO: Stop scaleio-gateway service on the second gateway $(date)"
juju-ssh 4 'sudo service scaleio-gateway stop || /bin/true' 2>/dev/null
sleep 10
echo "INFO: Check status scaleio-gateway service on the second gateway $(date)"
juju-ssh 4 sudo service scaleio-gateway status 2>/dev/null

check_haproxy_responses ${ip_addresses[@]}
echo "INFO: Check creation of cinder volume through gw1 $(date)"
check_volume_creation ha2_gw1 || ret=1

deactivate

trap - ERR

$my_dir/../scaleio-openstack/save_logs.sh

if [[ $ret != 0 ]] ; then
  echo "FINISH: Errors occured during the test."
  exit 1
fi

echo "FINISH: Success"
