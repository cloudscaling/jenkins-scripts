#!/bin/bash
my_dir="$(dirname "$0")"

source '/var/lib/jenkins/google-cloud-sdk/path.bash.inc'

cd tempest
. $my_dir/run-tempest.sh

exit $exit_status
