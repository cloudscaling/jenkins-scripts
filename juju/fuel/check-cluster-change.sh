#!/bin/bash -eux

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

source $my_dir/../functions
source $my_dir/../scaleio/static-checks

cdir="$(pwd)"
cd fuel-charms

cloud=${1:-"ec2"}
if [[ "${cloud}" == "gce" ]]; then
    instance_type="n1-standard-1"
    device_paths="/var/scaleio_disk"
else
    instance_type="i2.xlarge"
    device_paths="/dev/xvdb"
fi
machines=()

function provision_machines() {
    local new_mx=()
    echo "Provision machines: $*"
    while (( "$#" )); do
        mx=$(juju add-machine --constraints "instance-type=${instance_type}" 2>&1 | awk '{print $3}')
        echo "Machine $1 created: $mx"
        machines[$1]=${mx}
        new_mx+=(${mx})
        shift
    done

    # wait for machines up
    wait_for_machines ${new_mx[@]}
    
    # if not EC2:
    #       - prepare device for SDS (truncated file)
    #       - patch host name - in GCE hostname is too long, e.g. juju-023fae94-ef89-4b6d-8681-d9e462c7fae3-machine-2
    if [[ "${cloud}" == "gce" ]]; then
        for i in ${new_mx[@]}; do
            paths=$(echo ${device_paths} | sed 's/,/ /g')
            juju ssh $i "for p in ${paths}; do sudo rm -f \$p && sudo truncate --size 100G \$p; done" 2>/dev/null
            juju ssh $i "sudo sed -i 's/\(juju-\)\(.*\)\(machine.*\)/\1\3/g' /etc/hostname && sudo hostname -F /etc/hostname" 2>/dev/null
        done
    fi    
    
    # check kernel at one machine
    rm -f index.html
    wget -nv "--ftp-user=QNzgdxXix" "--ftp-password=Aw3wFAwAq3" ftp://ftp.emc.com/Ubuntu/2.0.5014.0/
    kernel=`juju ssh ${new_mx[0]} "uname -r" 2>/dev/null`
    kernel=`echo $kernel | sed 's/\r//'`
    if ! cat index.html | grep $kernel ; then
      echo "WARNING: driver for kernel $kernel not found on ftp.emc.com. Upgrade kernel to 4.2.0-30"
    
      # change kernel and reboot
      for m in ${new_mx[@]} ; do
        echo "--- Updating machine $m"
        juju ssh $m "sudo apt-get install -fy linux-image-4.2.0-30-generic linux-headers-4.2.0-30-generic &>/dev/null" 2>/dev/null
        juju ssh $m "sudo reboot" 2>/dev/null
      done
    
      # wait for machines up
      wait_for_machines ${new_mx[@]}
    fi
    rm -f index.html
}

trap catch_errors ERR

function save_logs() {
  # save status to file
  for mch in ${machines[@]:1} ; do
    name=fuel-node${mch}
    service_info="`juju service get ${name} || echo not_exists`"
    if [[ "${service_info}" != "not_exists" ]]; then
        mdir="$cdir/logs/$mch"
        mkdir -p "$mdir"
        juju ssh $mch 'cat /var/log/fuel-puppet-scaleio.log' > "$mdir/puppet-scaleio.log" 2>/dev/null
        juju ssh $mch 'cat /var/lib/hiera/defaults.yaml' > "$mdir/var-lib-hiera-defaults.log" 2>/dev/null
    fi
  done
}

function catch_errors() {
  local exit_code=$?
  save_logs
  exit $exit_code
}

function remove_node_service() {
    echo Remove service from machines $@
    while (( "$#" )); do
        echo Remove service from machine $1/${machines[$1]}
        name=fuel-node$1
        juju remove-service $name
        shift
    done    
 }

function deploy_node_service() {
    machine=${machines[$1]}
    name=fuel-node$1
    roles=$2
    service_info="`juju service get ${name} || echo not_exists`"
    if [[ "${service_info}" == "not_exists" ]]; then
        juju deploy local:trusty/fuel-node $name --to $machine
        juju add-relation fuel-master $name
    fi
    juju set $name roles="${roles}"
 }

deploy_counter=1

function configure_cluster() {
    mdms=""
    while (( "$#" )); do
        case "$1" in
            "compute")
                shift
                for i in `echo $1 | sed 's/,/ /g'`; do
                    deploy_node_service $i "compute"
                done
            ;;
            "primary-controller")
                shift
                deploy_node_service $1 "primary-controller cinder"
                mdms+=" ${machines[$1]}"
            ;;
            "controller")
                shift
                for i in `echo $1 | sed 's/,/ /g'`; do
                    deploy_node_service $i "controller cinder"
                    mdms+=" ${machines[$i]}"
                done
            ;;
            "mode")
                shift
                mode=$1
            ;;
        esac
        shift
    done

    sleep 15
    
    echo "Wait for services start: $(date)"
    wait_absence_status_for_services "executing|blocked|waiting|allocating"
    echo "Wait for services end: $(date)"

    juju set fuel-master deploy=$deploy_counter
    ((deploy_counter++))
    sleep 30
    
    echo "Wait for services start: $(date)"
    wait_absence_status_for_services "maintenance"
    echo "Wait for services end: $(date)"
    
    # check query_cluster output before exit on error if exists
    master_mdm=`get_master_mdm "echo ${mdms}"`
    echo "INFO: query cluster on machine $master_mdm"
    juju ssh $master_mdm 'scli --query_cluster --approve_certificate' 2>/dev/null
    
    # check for errors
    if juju status | grep "current" | grep error ; then
      echo "ERROR: Some services went to error state"
      juju ssh 0 sudo grep Error /var/log/juju/all-machines.log 2>/dev/null
      exit 1
    fi
    
    check-cluster "juju ssh" $master_mdm $mode
}


# prepare fuel node
provision_machines 0
juju deploy local:trusty/fuel-master --to ${machines[0]}
juju set fuel-master device-paths=${device_paths}


# 1+2 cluster
provision_machines 1 2 3
configure_cluster mode 1 primary-controller 1 compute 2,3

# 2+2 cluster
provision_machines 4
configure_cluster mode 1 primary-controller 1 compute 2,3 controller 4

# 3+2 cluster
provision_machines 5
configure_cluster mode 3 primary-controller 1 compute 2,3 controller 4,5

# 2+2 cluster
remove_node_service 1
configure_cluster mode 1 primary-controller 4 compute 2,3 controller 5

# 3+2 cluster
provision_machines 1
configure_cluster mode 3 primary-controller 4 compute 2,3 controller 1,5

# 4+2 cluster
provision_machines 6
configure_cluster mode 3 primary-controller 4 compute 2,3 controller 1,5,6

# 5+2 cluster
provision_machines 7
configure_cluster mode 5 primary-controller 4 compute 2,3 controller 1,5,6,7

# 4+2 cluster
remove_node_service 4
configure_cluster mode 3 primary-controller 1 compute 2,3 controller 5,6,7

# 3+2 cluster
remove_node_service 5
configure_cluster mode 3 primary-controller 1 compute 2,3 controller 6,7

# 3+1 cluster
remove_node_service 3
configure_cluster mode 3 primary-controller 1 compute 2 controller 6,7

save_logs
