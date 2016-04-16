#!/bin/bash

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

key=$(cat ~/.aws/config | grep aws_access_key_id | cut -d '=' -f 2)
sed -i "s\^aws_access.*$\aws_access = $key\m" tempest/etc/tempest.conf
key=$(cat ~/.aws/config | grep aws_secret_access_key | cut -d '=' -f 2)
sed -i "s\^aws_secret.*$\aws_secret = $key\m" tempest/etc/tempest.conf

cd tempest
timeout -s 9 6h $my_dir/run-tempest.sh

aws ec2 describe-volumes
aws ec2 describe-instances --filters Name=instance-state-name,Values=running

exit $exit_status
