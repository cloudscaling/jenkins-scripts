#!/bin/bash

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

source '/var/lib/jenkins/google-cloud-sdk/path.bash.inc'

cd tempest
timeout -s 9 2h $my_dir/run-tempest.sh

exit $exit_status
