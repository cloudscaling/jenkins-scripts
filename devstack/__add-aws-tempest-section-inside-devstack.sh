#!/bin/bash -e

ENV_FILE="cloudrc"
SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ServerAliveInterval=30"

source $ENV_FILE
SSH_DEST="ubuntu@$public_ip"
SSH="ssh -i kp $SSH_OPTS $SSH_DEST"
SCP="scp -i kp $SSH_OPTS"

echo "preparing conf"
echo -------------------------------------------------------------------------- $(date)
$SCP ~/scripts/create-tests-config.sh $SSH_DEST:ctc.sh
$SSH "/bin/bash ctc.sh"
