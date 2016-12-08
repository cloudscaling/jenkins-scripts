# Jenkins scripts

## Overview

This repository contains scripts that cat be run for testing.
Right now scripts are used by Jenkins - http://52.15.65.240:8080/


## Jenkins slaves

These scripts need next slaves:

- Slave with one executor to run Juju 1.25 jobs and Devstack jobs.
  This slave should be configured to access Amazon cloud under user 'jenkins'.
  In common case this slave is the jenkins master itself.

- Slave with one or more executors to run Juju 2.0 jobs and resource-consuming jobs (Fuel and TripleO CI's).
  It should be configured to access Amazon cloud as well and to run KVM virtual machines.
  It should be able to run at least 6 VM with configuration 2 cpu, 8GB of RAM, 2x100GB disks.
  How to prepare it is described below.


###How to prepare jenkin slave for resource-consuming jobs:

1. Prepare Server
  - Deploy ubuntu server 14.04 or higher
  - Enable firewall with allowing ssh ports

2. Prepare software:
  apt-get install -y git qemu-kvm

3. Prepare jenkins user to access from Jenkins master server:
  - Create jenkins user with certificate authentication only
  - Add the pub-key of master jenkins server into jenkins's user authorized_keys file (/home/jenkins/.ssh/authorized_keys)

4. Allow ssh to skip cert-check and don't save host signatures in the known host file:
  Example of ssh config:
    cat /home/jenkins/.ssh/config
    Host *
    StrictHostKeyChecking no
    UserKnownHostsFile=/dev/null

5. Allow jenkins user to run deploy under privileged user, add to sudoers file:

  ```
  #FUEL CI:
  jenkins ALL=(ALL) NOPASSWD: /home/jenkins/workspace/*/jenkins-scripts/fuel/provision_fuel.sh
  jenkins ALL=(ALL) NOPASSWD: /home/jenkins/workspace/*/jenkins-scripts/fuel/cleanup_env.sh
  Defaults!/home/jenkins/workspace/*/jenkins-scripts/fuel/provision_fuel.sh env_keep+="WORKSPACE FUEL_*"
  Defaults!/home/jenkins/workspace/*/jenkins-scripts/fuel/cleanup_env.sh env_keep+="WORKSPACE FUEL_*"

  For TRIPLEO CI:
  jenkins ALL=(ALL) NOPASSWD:SETENV: /home/jenkins/workspace/*/redhat-kvm/deploy_all.sh
  jenkins ALL=(ALL) NOPASSWD:SETENV: /home/jenkins/workspace/*/redhat-kvm/clean_env.sh
  ```

6. On the Jenkins master add new builder, with options:
  - limit number of executor processess with reasonable number, e.g. 3 for the server with 128GB RAM, 32 logical CPUs and a RAID on 2 SSD disks.
  - root of remote filesystem: /home/jenkins
  - The way to run jenkins slave agent: Launch jenkins via execution of command on the master:
    ssh -v jenkins@158.69.124.47 'cd ~ && wget http://52.15.65.240:8080/jnlpJars/slave.jar && java -jar ~/slave.jar'
    (put your real IP/name of jenkins slave server)
    In unknown reason the the other ways didn't work in our case.
  - In case if you want to restrict what jobs should be run on the slave use 'Job restriction', e.g. by Job name matching to a regular expression ('ScaleIO-Fuel-CI.*' for example)


## Folder descriptions

### 'jenkins-jobs' folder

Files for jenkins job builder to setup CI jobs on jenkins

```
jenkins_jobs.ini - configuration file for jjb
Makefile - make file for jjb
jobs/update-jenkins-jobs.yaml - job that runs JJB (jenkins job builder) and updates CI
jobs/defaults.yaml - default parameters for all jobs
jobs/devstack-extended.yaml - two jobs. each builds VM in Amazon, deploys devstack there with ec2/gce, and runs ec2/gce tests
jobs/ec2api-aws.yaml - run ec2 functional tests against Amazon
jobs/gceapi-gcloud.yaml - run gce functinal tests against Google cloud
jobs/github_macros.yaml - macros with repositories definitions for jobs
jobs/puppet-checks.yaml - two jobs with unit tests for puppet-scaleio and puppet-scaleio-openstack
jobs/juju-unit-tests.yaml - runs unit tests in juju repository
jobs/juju-destroy-environment.yaml - one job for destroying juju 1.25 environment, another checks periodically for stucked resources and kill them
jobs/ScaleIO-Juju-checks.yaml - several jobs for main checks of ScaleIO by Juju
jobs/ScaleIO-OpenStack.yaml - several jobs for checking ScaleIO by Juju with OpenStack
jobs/ScaleIO-Fuel-Emulators.yaml - runs fuel emulator with Juju
jobs/ScaleIO-Fuel-CI.yaml - runs Fuel with ScaleIO on standalone slave
jobs/ScaleIO-TripleO-CI.yaml - runs TripleO with ScaleIO on standalone slave
```

### 'devstack' folder

This folder contains scripts for checking ec2/gce against devstack

```
devstack-ec2 - configuration file for devstack with ec2 enabled (localrc)
devstack-gce - configuration file for devstack with gce enabled (localrc)

run.sh - orchestrating script to run ec2/gce tests agains devstack. it calls next several files:
create-instance-for-devstack-cloud.sh
install-devstack.sh
run-tempest-inside-devstack.sh
save-logs-from-devstack.sh
cleanup-devstack-cloud.sh
```

### 'tempest' folder

Files to run tempest against real clouds: Amazon/Google Compute Engine

```
install-tempest.sh - installs tempest locally in virtual env
run-tempest.sh - runs tempest
subunit2jenkins.py - python script to convert result for jenkins graphs
```

### 'fuel' folder

Files to help deploy and check full Fuel deployment.
It supports versions: 6.1, 7.0, 8.0, 9.0
These scripts need some VM images to run deployemnt.
You need to download Mirantis OpenStack (MOS) iso files into /home/jenkins/iso folder (on a slave),
Files can be found at the official site: https://www.mirantis.com/software/openstack/download/
Exmaple of the dir content: MirantisOpenStack-6.1.iso MirantisOpenStack-7.0.iso MirantisOpenStack-8.0.iso MirantisOpenStack-9.0.iso

```
run-scaleio.sh - runs Fuel deployment and runs script that passed as a first argument
check-openstack.sh          - runs OpenStack tests
check-openstack-stub.sh     - copies scripts on fuel slave nodes (first controller) and run it there
cleanup_env.sh              - helping script to cleanup deployed Fuel environment
fuel-utils                  - utilities to configure Fuel testing environment
prepare_plugin.sh           - it is run on Fuel mster node, it downloads, builds and installs the plugin
provision_fuel.sh           - prepares ssh-keys to access Fuel master node
run-os-task.sh              - helping scrpt to tune flavors, etc (not used now)
set_network_parameters.py   - helping script to modify yaml-fiel with Fuel network parameters
set_node_network.py         - helping script to modify yaml-file with Fuel assigned networks 
set_node_volumes_layout.py  - helping script to modify yaml-file with Fuel slave nodes volume layout
set_plugin_parameters.py    - helping script to modify yaml-file with plugin settings
test-cluster.sh             - main script that contains main test workflow, it is run on Fuel master node
test-cluster-stub.sh        - helping script that copies test-cluster.sh from Jenkins node to Fuel master and run it there


### 'tripleo' folder

Files to help deploy and check full TripleO deployment.
It supports Mitaka and Newton versions.
These scripts also need some VM image to run deployemnt.
Right now it is configured to use /var/lib/images/CentOS-7-x86_64-GenericCloud-1607.qcow2

run-scaleio.sh - runs TripleO deployment from cloned repository
check-scaleio-proxy.sh - copies next file to undercloud and runs it there
check-scaleio.sh - runs various checks for ScaleIO (should be run on the undercloud)
```

### 'juju' folder

This folder contains scripts, helpers and other folders to deploy and check various scenario with Juju

```
functions - helpers for setting up and checking of Juju environment
functions-juju - 'base' file with juju functions
functions-juju1 - functions that has own behavior in juju 1.25
functions-juju2 - functions that has own behavior in juju 2.0
functions-openstack - helpers to set up and check OpenStack part of environment
run-scaleio-openstack.sh - bootstraps environment, runs provided check as a first parameter and runs checks for ScaleIO cluster with OpenStack
run-scaleio.sh - bootstraps environment and runs provided check as a first parameter
save_logs.sh - saves juju logs from all machines
```

### 'jujuj/fuel' folder

Contains scripts for emulating fuel deployment without fuel on Amazon machines provided by Juju

```
deploy-fuel.sh - deploys Juju environment with charms from fuel-charms repository and checks parameters that should be passed from fuel plugin to ScaleIO
check-cluster-change.sh - deploys Juju environment with charms from fuel-charms repository and checks various cluster changing/switching
functions - helpers for previous scripts
```

### 'juju/scaleio' folder

Contains scripts for ScaleIO checking with several scenarios

```
__check-cache-parameters.sh - checks caching parameters
__check-capacity-alerts.sh - checks alerts parameters
__check-mdm-password.sh - checks changing password for admin user of mdm
__check-protection-domains.sh - checks protection domains
__check-storage-pool-parameters.sh - checks parameters of storage pools
__check-storage-pools.sh - checks storage pools
deploy-check-parameters.sh - deploys machines and runs all previous scripts to check
deploy-check-mdm-cluster.sh - check switching of MDM's cluster
deploy-multi-interfaces.sh - it was a try to check how ScaleIO will work with several interfaces. This script is not finished and saved only as an example.
deploy-scaleio-cluster.sh - deploys ScaleIO cluster
scaleio-amazon.yaml - bundle for deploying ScaleIO cluster
static-checks - helpers for check state of ScaleIO cluster
```

### 'juju/scaleio-gw-haproxy' folder

Contains only one script for checking haproxy+gateway on two nodes: deploy-check-haproxy.sh

### 'juju/scaleio-openstack' folder

Contains scripts for deploy and check of deployment ScaleIO with OpenStack by Juju

```
openstack-scaleio-amazon.yaml - bundle of this configuration
deploy-bundle.sh - deploys configuration as a Juju bundle
deploy-manual.sh - deploys configuration in manual way, e.g. adds and relates charms through CLI
check-openstack.sh - checks OpenStack features of this configuration
functions - empty file for now. created to place common helpers for scripts in this folder
reconfigure-to-existing-cluster.sh - script that emulates configuring OpenStack to existing ScaleIO cluster
save_logs.sh - saves OpenStack's logs from all machines
```

run-tempest.sh - downloads and runs tempest tests. it needs next folder to work properly:

### 'juju/scaleio-openstacl/tempest' folder

Contains various helper files to run tempest tests

```
accounts.yaml
excludes.juno
excludes.kilo
excludes.liberty
excludes.mitaka
format_test_list.py
__setup_cloud_accounts.sh
tempest.conf
```
