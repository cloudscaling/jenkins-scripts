#!/bin/bash -ux

scaleio_dir=`ls /etc/fuel/plugins/ | grep scaleio`

if [ -z "${scaleio_dir}" ] ; then
  echo There is no scaleio plugin installed
  exit -1
fi

FACTERLIB=/etc/fuel/plugins/${scaleio_dir}/puppet/modules/scaleio_openstack/lib/facter puppet apply --modulepath=/etc/puppet/modules:/etc/fuel/plugins/${scaleio_dir}/puppet/modules --detailed-exitcodes --trace --no-report --debug --evaltrace  /etc/fuel/plugins/${scaleio_dir}/puppet/manifests/os.pp
res=$?
if [[ $res != 0 && $res != 2 ]]; then
  echo puppet failed with the code $res
  exit $res
fi
