#!/bin/bash

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"
source $my_dir/../functions

echo "--------------------------------------------------- Save LOGS ---"

# save status to file
log_dir=$WORKSPACE/logs
rm -rf $log_dir
mkdir $log_dir
juju-status > $log_dir/juju_status.log
juju-ssh 0 sudo cat /var/log/juju/all-machines.log > $log_dir/all-machines.log 2>/dev/null

for mch in $(juju-get-machines) ; do
  mkdir -p $log_dir/$mch
  juju-ssh $mch sudo cat /var/log/juju/machine-$mch.log > $log_dir/$mch/juju-machine-$mch.log 2>/dev/null
done

# try to save logs from cinder and nova nodes
function save_logs() {
  local service=$1
  for mch in `juju-status-json $service | jq .machines | jq keys | tail -n +2 | head -n -1 | sed -e "s/[\",]//g"` ; do
    echo "Save logs - Service: $service  Machine: $mch"
    if [[ $service =~ 'nova' ]] ; then
      local dirs='/var/log/nova /etc/nova'
      echo "  version info:"
      juju-ssh $mch "dpkg -s python-nova | grep 'Version:'" 2>/dev/null
      juju-ssh $mch "virsh --version || /bin/true" 2>/dev/null
    elif [[ $service =~ 'cinder' ]] ; then
      local dirs='/var/log/cinder /etc/cinder'
      echo "  version info:"
      juju-ssh $mch "dpkg -s python-cinder | grep 'Version:'" 2>/dev/null
    elif [[ $service =~ 'scaleio-gw' ]] ; then
      local dirs='/opt/emc/scaleio/gateway/logs /etc/haproxy/haproxy.cfg'
    else
      continue
    fi
    echo "  dirs: $dirs"

    juju-ssh $mch "rm -f logs.* ; sudo tar -cf logs.tar $dirs ; gzip logs.tar" 2>/dev/null
    rm -f logs.tar.gz
    juju-scp $mch:logs.tar.gz logs.tar.gz
    cdir=`pwd`
    mkdir -p $log_dir/$mch
    pushd $log_dir/$mch
    tar -xf $cdir/logs.tar.gz
    popd
    rm -f logs.tar.gz
  done
}

for service in nova-compute nova-cloud-controller cinder scaleio-gw ; do
  save_logs $service
done
