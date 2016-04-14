#!/bin/bash

echo "--------------------------------------------------- Save LOGS ---"

# save status to file
rm -rf logs
mkdir logs
juju status > logs/juju_status.log
juju ssh 0 sudo cat /var/log/juju/all-machines.log > logs/all-machines.log


# try to save logs from cinder and nova nodes
function save_logs() {
  local service=$1
  for mch in `juju status $service --format json | jq .machines | jq keys | tail -n +2 | head -n -1 | sed -e "s/[\",]//g"` ; do
    echo "Save logs - Service: $service  Machine: $mch"
    if [[ $service =~ 'nova' ]] ; then
      local srv='nova'
    elif [[ $service =~ 'cinder' ]] ; then
      local srv='cinder'
    else
      continue
    fi
    echo "  service: $srv"

    juju ssh $mch "rm -f logs.* ; sudo tar -cf logs.tar /var/log/$srv /etc/$srv ; gzip logs.tar"
    rm -f logs.tar.gz
    juju scp $mch:logs.tar.gz logs.tar.gz
    mkdir -p logs/$mch
    pushd logs/$mch
    tar -xf ../../logs.tar.gz
    popd
    rm -f logs.tar.gz
  done
}

for service in nova-compute nova-cloud-controller cinder ; do
  save_logs $service
done
