#!/bin/bash
my_dir="$(dirname "$(readlink -e "$0")")"

source '/var/lib/jenkins/google-cloud-sdk/path.bash.inc'

cd tempest
. $my_dir/run-tempest.sh

exit $exit_status
