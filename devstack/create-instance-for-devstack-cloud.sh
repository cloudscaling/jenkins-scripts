#!/bin/bash -e

ENV_FILE="cloudrc"
VM_CIDR="192.168.130.0/24"
VM_TYPE="c4.xlarge"
IMAGE_ID="ami-d05e75b8"

rm -rf logs

trap catch_errors ERR;

function catch_errors() {
  local exit_code=$?
  echo "Errors!" $exit_code $@

  /var/lib/jenkins/scripts/cleanup-devstack-cloud.sh

  exit $exit_code
}

function get_value_from_json() {
  local cmd_out=$($1 | jq $2)
  eval "echo $cmd_out"
}


if [ -f $ENV_FILE ]; then
  echo "Previous environment found. Please check and cleanup."
  exit 1
fi

touch $ENV_FILE
echo -------------------------------------------------------------------------- $(date)

cmd="aws ec2 create-vpc --cidr-block $VM_CIDR"
vpc_id=$(get_value_from_json "$cmd" ".Vpc.VpcId")
echo "VPC_ID: $vpc_id"
echo "vpc_id=$vpc_id" >> $ENV_FILE

cmd="aws ec2 create-subnet --vpc-id $vpc_id --cidr-block $VM_CIDR"
subnet_id=$(get_value_from_json "$cmd" ".Subnet.SubnetId")
echo "SUBNET_ID: $subnet_id"
echo "subnet_id=$subnet_id" >> $ENV_FILE
sleep 2

cmd="aws ec2 create-internet-gateway"
igw_id=$(get_value_from_json "$cmd" ".InternetGateway.InternetGatewayId")
echo "IGW_ID: $igw_id"
echo "igw_id=$igw_id" >> $ENV_FILE

aws ec2 attach-internet-gateway --internet-gateway-id $igw_id --vpc-id $vpc_id

cmd="aws ec2 describe-route-tables --filters Name=vpc-id,Values=$vpc_id"
rtb_id=$(get_value_from_json "$cmd" ".RouteTables[0].RouteTableId")
echo "RTB_ID: $rtb_id"

aws ec2 create-route --route-table-id $rtb_id --destination-cidr-block "0.0.0.0/0" --gateway-id $igw_id

key_name="testkey-$(cat /dev/urandom | tr -cd 'a-f0-9' | head -c 8)"
echo "key_name=$key_name" >> $ENV_FILE
key_result=$(aws ec2 create-key-pair --key-name $key_name)

kp=$(get_value_from_json "echo $key_result" ".KeyMaterial")
echo $kp | sed 's/\\n/\'$'\n''/g' > kp
chmod 600 kp


cmd=$(aws ec2 run-instances --image-id $IMAGE_ID --key-name $key_name --instance-type $VM_TYPE --block-device-mappings '[{"DeviceName":"/dev/sdh","Ebs":{"VolumeSize":20,"DeleteOnTermination":true}}]' --subnet-id $subnet_id --associate-public-ip-address)
instance_id=$(get_value_from_json "echo $cmd" ".Instances[0].InstanceId")
echo "INSTANCE_ID: $instance_id"
echo "instance_id=$instance_id" >> $ENV_FILE

time aws ec2 wait instance-running --instance-ids $instance_id
echo "Instance ready."

cmd_result=$(aws ec2 describe-instances --instance-ids $instance_id)
public_ip=$(get_value_from_json "echo $cmd_result" ".Reservations[0].Instances[0].PublicIpAddress")
echo "Public IP: $public_ip"
echo "public_ip=$public_ip" >> $ENV_FILE
group_id=$(get_value_from_json "echo $cmd_result" ".Reservations[0].Instances[0].SecurityGroups[0].GroupId")
echo "Group ID: $group_id"

aws ec2 authorize-security-group-ingress --group-id $group_id --cidr 0.0.0.0/0 --protocol tcp --port 22
aws ec2 authorize-security-group-ingress --group-id $group_id --cidr $public_ip/32 --protocol tcp --port 0-65535

for port in 8774 8776 8788 5000 9696 8080 9292 35357 ; do
  aws ec2 authorize-security-group-ingress --group-id $group_id --cidr 0.0.0.0/0 --protocol tcp --port $port
done

trap - ERR;

echo "Ready to install devstack"