#!/bin/bash -e

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

source $my_dir/../functions
source $my_dir/../scaleio/static-checks

export USERNAME='admin'
export PASSWORD="Default_password"

echo "INFO: start $(date)"

echo "Create machines"
m1=$(create_machine 0 2)
echo "Machine created: $m1"
m2=$(create_machine 0 2)
echo "Machine created: $m2"
m3=$(create_machine 0 2)
echo "Machine created: $m3"

wait_for_machines $m1 $m2 $m3

# deploy fake charms to prevent machines removing
juju deploy ubuntu --to $m1
juju service add-unit ubuntu --to $m2
juju service add-unit ubuntu --to $m3

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

# machines are not removed. all environment will be destroyed by calling script.

exit $errors
