#!/bin/bash

test_suite=$1
concurrency=${2:-1}

ENV_FILE="cloudrc"
SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ServerAliveInterval=30"

source $ENV_FILE
SSH_DEST="ubuntu@$public_ip"
SSH="ssh -i kp $SSH_OPTS $SSH_DEST"
SCP="scp -i kp $SSH_OPTS"

rm -f *.xml
echo "running tests"
echo -------------------------------------------------------------------------- $(date)
$SSH "echo \"-e git+https://github.com/openstack/ec2-api.git#egg=ec2_api\" >> /opt/stack/tempest/requirements.txt"
$SSH "echo \"-e git+https://github.com/openstack/gce-api.git#egg=gce_api\" >> /opt/stack/tempest/requirements.txt"
$SSH "echo \"google-api-python-client\" >> /opt/stack/tempest/requirements.txt"
$SSH "cd /opt/stack/tempest; tox -eall-plugin -- $test_suite --concurrency=$concurrency"
exit_code=$?
echo -------------------------------------------------------------------------- $(date)

suite=`basename "$(readlink -f .)"`
$SSH "sudo pip install extras"
$SSH "cd /opt/stack/tempest ; testr last --subunit | subunit-1to2" | python $WORKSPACE/jenkins-scripts/tempest/subunit2jenkins.py -o test_result.xml -s $suite
