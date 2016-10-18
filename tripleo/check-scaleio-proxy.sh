#!/bin/bash -e

# args for this script are ssh opts and addr for the undercloud
ssh_addr="$1"
shift
ssh_opts="$@"

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

cd "$my_dir/../.."
tar cf js.tar jenkins-scripts
scp $ssh_opts js.tar $ssh_addr:/home/stack/js.tar
ssh $ssh_opts $ssh_addr "sudo -u stack tar xf /home/stack/js.tar -C /home/stack"
rm -f js.tar
ssh $ssh_opts $ssh_addr "cd /home/stack && sudo -u stack ./jenkins-scripts/tripleo/check-scaleio.sh"
