#!/bin/bash -e

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"
my_name="$(basename "$0")"

source $my_dir/../functions

cd juju-scaleio

trap catch_errors ERR EXIT
function catch_errors() {
  local exit_code=$?
  juju remove-service scaleio-mdm || /bin/true
  wait_for_removed "scaleio-mdm" || /bin/true
  trap - ERR EXIT
  exit $exit_code
}

echo "INFO: Deploy MDM to 0"
juju deploy local:trusty/scaleio-mdm --to 0
wait_status

echo "INFO: check mdm password"
if ! mdm_output=`juju ssh 0 "scli --login --username $USERNAME --password $PASSWORD --approve_certificate >/dev/null && scli --query_all" 2>/dev/null` ; then
  echo "ERROR: ($my_name:$LINENO) Couldn't login or execute 'scli --query_all'"
  echo "$mdm_output"
  exit 1
fi
echo "INFO: Success"

echo "INFO: change password"
new_password="No_password"
juju set scaleio-mdm password=$new_password
wait_status

ret=0

echo "INFO: check that old password doesn't work"
if mdm_output=`juju ssh 0 "scli --login --username $USERNAME --password $PASSWORD >/dev/null " 2>/dev/null` ; then
  ret=1
  echo "ERROR: ($my_name:$LINENO) Illegal success with old password"
  echo "$mdm_output"
elif [[ "$mdm_output" != *"Permission denied"* ]] ; then
  ret=2
  echo "ERROR: ($my_name:$LINENO) Another error was occured"
  echo "$mdm_output"
else
  echo "INFO: Success"
fi

echo "INFO: check new password works"
if ! mdm_output=`juju ssh 0 "scli --login --username $USERNAME --password $new_password >/dev/null && scli --query_all" 2>/dev/null` ; then
  ret=3
  echo "ERROR: ($my_name:$LINENO) Couldn't login or execute 'scli --query_all'"
  echo "$mdm_output"
else
  echo "INFO: Success"
fi

juju remove-service scaleio-mdm
wait_for_removed "scaleio-mdm"

trap - ERR EXIT
exit $ret
