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

echo "Create and attach volumes"
i=0
for instance in $instances ; do
  if [[ $i != 0 ]] ; then
    xvdf=$(aws ec2 create-volume --size 100 --region us-east-1 --availability-zone us-east-1c --volume-type gp2 | grep VolumeId | awk '{print$2}' | sed "s/\"//;s/\",//")
    xvdg=$(aws ec2 create-volume --size 100 --region us-east-1 --availability-zone us-east-1c --volume-type gp2 | grep VolumeId | awk '{print$2}' | sed "s/\"//;s/\",//")
    fail=0
    while ! output=`aws ec2 attach-volume --volume-id $xvdf --instance-id $instance --device /dev/xvdf 2>/dev/null` ; do
      if ((fail >= 12)); then
        echo "ERROR: $output"
        break
      fi
      sleep 10
      ((++fail))
    done
    while ! output=`aws ec2 attach-volume --volume-id $xvdg --instance-id $instance --device /dev/xvdg 2>/dev/null` ; do
      if ((fail >= 12)); then
        echo "ERROR: $output"
        break
      fi
      sleep 10
      ((++fail))
    done
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
run-test "$my_dir"/__check-storage-pool-parameters.sh $m1 $m2
run-test "$my_dir"/__check-cache-parameters.sh $m1 $m2 $m3

if (( errors > 0 )) ; then /bin/false ; fi
