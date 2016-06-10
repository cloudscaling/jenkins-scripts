#!/bin/bash -e

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

source $my_dir/../functions
source $my_dir/../scaleio/static-checks

export USERNAME='admin'
export PASSWORD="Default_password"

echo "INFO: start $(date)"

echo "Create machines"
m1=$(juju add-machine --constraints "instance-type=t2.medium" zone=us-east-1c 2>&1 | awk '{print $3}')
echo "Machine created: $m1"
m2=$(juju add-machine --constraints "instance-type=t2.medium" zone=us-east-1c 2>&1 | awk '{print $3}')
echo "Machine created: $m2"
m3=$(juju add-machine --constraints "instance-type=t2.medium" zone=us-east-1c 2>&1 | awk '{print $3}')
echo "Machine created: $m3"
#m4=$(juju add-machine --constraints "instance-type=c3.4xlarge" 2>&1 | awk '{print $3}')
#echo "Machine created: $m4"
#m5=$(juju add-machine --constraints "instance-type=c3.4xlarge" 2>&1 | awk '{print $3}')
#echo "Machine created: $m5"

wait_for_machines $m1 $m2 $m3 #$m4 $m5

instances=`juju status | grep instance-id | awk '{print$2}'`

function wait_state() {
  volume_id=$1
  state=$2
  local fail=0
  while ! aws ec2 describe-volumes --volume-id $volume_id | grep "State" | grep -q $state ; do
    if ((fail >= 12)); then
      echo "ERROR: Volume $volume_id isn't $state"
      echo aws ec2 describe-volumes --volume-id $volume_id
      exit 1
    fi
    sleep 10
    ((++fail))
  done
}

i=0
for instance in $instances ; do
  if [[ $i != 0 ]] ; then
    echo "Creating volumes for instance $instance"
    volume1=$(aws ec2 create-volume --size 100 --region us-east-1 --availability-zone us-east-1c --volume-type gp2 | grep 'VolumeId' | sed 's/[,\"]//g' | awk '{print$2}')
    volume2=$(aws ec2 create-volume --size 100 --region us-east-1 --availability-zone us-east-1c --volume-type gp2 | grep 'VolumeId' | sed 's/[,\"]//g' | awk '{print$2}')
    wait_state $volume1 "available"
    wait_state $volume2 "available"

    echo "Attaching volumes to instance $instance"
    aws ec2 attach-volume --volume-id $volume1 --instance-id $instance --device /dev/xvdf 1>/dev/null
    aws ec2 attach-volume --volume-id $volume2 --instance-id $instance --device /dev/xvdg 1>/dev/null
    wait_state $volume1 "attached"
    wait_state $volume2 "attached"

    echo "Adding DeleteOnTermination attribute for instance $instance"
    aws ec2 modify-instance-attribute --instance-id $instance --block-device-mappings "[{\"DeviceName\": \"/dev/xvdf\",\"Ebs\":{\"DeleteOnTermination\":true}}]" 1>/dev/null
    aws ec2 modify-instance-attribute --instance-id $instance --block-device-mappings "[{\"DeviceName\": \"/dev/xvdg\",\"Ebs\":{\"DeleteOnTermination\":true}}]" 1>/dev/null
  fi
  ((++i))
done

# deploy fake charms to prevent machines removing
juju deploy ubuntu --to $m1
juju service add-unit ubuntu --to $m2
juju service add-unit ubuntu --to $m3
#juju service add-unit ubuntu --to $m4
#juju service add-unit ubuntu --to $m5

errors=0

function run-test() {
  echo "INFO: $1 $(date)"
  $@ || (( ++errors ))
}

run-test "$my_dir"/__check-capacity-alerts.sh
run-test "$my_dir"/__check-mdm-password.sh
run-test "$my_dir"/__check-protection-domains.sh $m1 $m2
#run-test "$my_dir"/__check-storage-pool-parameters.sh $m1 $m2
#run-test "$my_dir"/__check-cache-parameters.sh $m1 $m2 $m3

exit $errors
