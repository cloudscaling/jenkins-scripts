# Jenkins scripts

## Overview

This repository contains scripts that cat be run for testing.
Right now scripts are used by Jenkins - http://52.15.65.240:8080/


### 'jenkins-jobs' folder

Files for jenkins job builder to setup CI jobs on jenkins


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


### 'devstack' folder

This folder contains scripts for checking ec2/gce against devstack


devstack-ec2 - configuration file for devstack with ec2 enabled (localrc)
devstack-gce - configuration file for devstack with gce enabled (localrc)

run.sh - orchestrating script to run ec2/gce tests agains devstack. it calls next several files:
create-instance-for-devstack-cloud.sh
install-devstack.sh
run-tempest-inside-devstack.sh
save-logs-from-devstack.sh
cleanup-devstack-cloud.sh

### 'tempest' folder

Files to run tempest against real clouds: Amazon/Google Compute Engine

install-tempest.sh - installs tempest locally in virtual env
run-tempest.sh - runs tempest
subunit2jenkins.py - python script to convert result for jenkins graphs



### 'fuel' folder

check-openstack.sh
check-openstack-stub.sh
cleanup_env.sh
fuel-utils
prepare_plugin.sh
provision_fuel.sh
README
run-os-task.sh
run-scaleio.sh
set_network_parameters.py
set_node_network.py
set_node_volumes_layout.py
set_plugin_parameters.py
test-cluster.sh
test-cluster-stub.sh


### 'tripleo' folder

check-scaleio-proxy.sh
check-scaleio.sh
run-scaleio.sh




-juju

functions
functions-juju
functions-juju1
functions-juju2
functions-openstack
run-scaleio-openstack.sh
run-scaleio.sh
save_logs.sh

--fuel
check-cluster-change.sh
deploy-fuel.sh
functions

--scaleio
__check-cache-parameters.sh
__check-capacity-alerts.sh
__check-mdm-password.sh
__check-protection-domains.sh
__check-storage-pool-parameters.sh
__check-storage-pools.sh
deploy-check-mdm-cluster.sh
deploy-check-parameters.sh
deploy-multi-interfaces.sh
deploy-scaleio-cluster.sh
scaleio-amazon.yaml
static-checks

--scaleio-gw-haproxy
deploy-check-haproxy.sh

--scaleio-openstack
check-openstack.sh
deploy-bundle.sh
deploy-manual.sh
functions
openstack-scaleio-amazon.yaml
reconfigure-to-existing-cluster.sh
run-tempest.sh
save_logs.sh
---tempest
accounts.yaml
excludes.juno
excludes.kilo
excludes.liberty
excludes.mitaka
format_test_list.py
__setup_cloud_accounts.sh
tempest.conf






