#!/bin/bash -e

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

USERNAME='admin'
PASSWORD="Default_password"

source $my_dir/../functions

cd juju-scaleio

echo "---------------------------------------------------------------- Deploy MDM ---"
juju deploy local:trusty/scaleio-mdm --to 0

wait_status

rm -f mdm-errors
touch mdm-errors

echo "------------------------------------------------------- check mdm password  ---"
if ! mdm_output=`juju ssh 0 "scli --login --username $USERNAME --password $PASSWORD --approve_certificate >/dev/null ; scli --query_all" 2>/dev/null` ; then
  echo "ERROR: Couldn't login or execute 'scli --query_all'"
  echo "$mdm_output"
  exit 1
fi
echo Success

echo "----------------------------------------------------------- change password ---"
new_password="No_password"
juju set scaleio-mdm password=$new_password
sleep 5

echo "---------------------------------------------------------------- wait hooks ---"
wait_status

echo "------------------------------------------- check old password doesn't work ---"
if mdm_output=`juju ssh 0 "scli --login --username $USERNAME --password $PASSWORD >/dev/null " 2>/dev/null` ; then
  echo "ERROR: Illegal with old password" >> mdm-errors
  echo "$mdm_output" >> mdm-errors
elif [[ "$mdm_output" != *"Permission denied"* ]] ; then
  echo "ERROR: Some error was occured" >> mdm-errors
  echo "$mdm_output" >> mdm-errors
else
  echo Success
fi

echo "-------------------------------------------------- check new password works ---"
if ! mdm_output=`juju ssh 0 "scli --login --username $USERNAME --password $new_password >/dev/null ; scli --query_all" 2>/dev/null` ; then
  echo "ERROR: Couldn't login or execute 'scli --query_all'" >> mdm-errors
  echo "$mdm_output" >> mdm-errors
else
  echo Success
fi

juju remove-service scaleio-mdm
wait_for_removed "scaleio-mdm"

if [ -s mdm-errors ] ; then
  cat mdm-errors
  exit 1
fi
