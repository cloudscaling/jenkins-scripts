#!/bin/bash

set -ux

my_dir="$(dirname "$0")"
mos=${1:-'MirantisOpenStack-6.1.iso'}
nodes=${2:-6}

if [[ "`whoami`" != 'root' ]] ; then
  echo Provisioning should be run under root
  exit -1
fi

fuel_master='10.20.0.2'

if [ -f /home/jenkins/.ssh/known_hosts ] ; then
  ssh-keygen -f /home/jenkins/.ssh/known_hosts  -R $fuel_master
fi

if [ -f /root/.ssh/known_hosts ] ; then
  ssh-keygen -f /root/.ssh/known_hosts  -R $fuel_master
fi

pushd ${my_dir}/fuel-kvm
  if ! ./deploy_fuel.sh ${my_dir}/${mos} ${nodes} ; then
    echo ERROR: failed to deploy environment
    popd
    exit -1
  fi
popd

ssh_opts='-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null'
id_rsa_pub_key=$(cat /home/jenkins/.ssh/id_rsa.pub)
ssh_cmd="mkdir -p ~/.ssh && chmod 0644 ~/.ssh && echo ${id_rsa_pub_key} > ~/.ssh/authorized_keys && chmod 0644 ~/.ssh/authorized_keys"
offending_key=`sshpass -pr00tme ssh ${ssh_opts} root@${fuel_master} ${ssh_cmd} 2>&1 | awk -F ':' '/Offending ECDSA key/ {print($2)}'`
if [[ $? != 0 ]] ; then
  if [ -n "${offending_key}" ] ; then
    sed -i "${offending_key}d" ~/.ssh/known_hosts
  else
    echo ERROR: failed to add ssh key to fuel known hosts
    echo ${offending_key}
    exit -1
  fi
  # retry
  if ! sshpass -pr00tme ssh ${ssh_opts} root@${fuel_master} ${ssh_cmd} ; then
    echo ERROR: failed to add ssh key to fuel known hosts
    exit -1
  fi
fi

