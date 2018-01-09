#!/bin/bash

PATH=$PATH:/usr/local/bin

## Install core O/S packages
if [ ! -f /usr/bin/sshpass ] ; then
  [ `which yum` ] && yum install -y sshpass
  [ `which apt-get` ] && apt-get -y install sshpass
fi

which pip &> /dev/null
if [ $? -ne 0 ] ; then
  [ `which yum` ] && $(yum install -y epel-release; yum install -y python-pip)
  [ `which apt-get` ] && apt-get -y update && apt-get -y install python-pip
fi
pip install --upgrade pip
pip install awscli --ignore-installed six



## Save off other cluster details in prep for configuration
echo ${cluster_name} > /tmp/clustername
echo Confluent Open Source > /tmp/cedition
echo Disabled > /tmp/csecurity
[ "Disabled" = 'Disabled' ] && rm /tmp/csecurity
echo 3.3.0 > /tmp/cversion

##  cfn-init downloads everything
##  and then we're off to the races
cfn-init -v          --stack ${cluster_name}-BrokerStack-1X758P9YFQL3V         --resource NodeLaunchConfig          --region us-west-2
AMI_SBIN=/tmp/sbin

## Prepare the instance
$AMI_SBIN/prep-cp-instance.sh
. $AMI_SBIN/prepare-disks.sh

## Wait for all nodes to come on-line
$AMI_SBIN/wait-for-child-resource.sh ${cluster_name} ZookeeperStack Nodes
$AMI_SBIN/wait-for-child-resource.sh ${cluster_name} BrokerStack Nodes

## Now find the private IP addresses of all deployed nodes
##   (generating /tmp/cphosts and /tmp/<role> files)
$AMI_SBIN/gen-cluster-hosts.sh ${cluster_name}

## Tag the instance (now that we're sure of launch index)
##   NOTE: ami_launch_index is correct only within a single subnet)
instance_id=$(curl -f http://169.254.169.254/latest/meta-data/instance-id)
ami_launch_index=$(curl -f http://169.254.169.254/latest/meta-data/ami-launch-index)
launch_node=$(grep -w `hostname -s` /tmp/brokers | awk '{print $2}')
if [ -n "$launch_node" ] ; then
  launch_index=$${launch_node#*NODE}
else
  launch_index=$${ami_launch_index}
fi
if [ -n "$instance_id" ] ; then
  instance_tag=${cluster_name}-broker-$${launch_index}
  aws ec2 create-tags --region us-west-2 --resources $instance_id --tags Key=Name,Value=$instance_tag
fi
## Run the steps to install the software,
## then configure and start the services
$AMI_SBIN/cp-install.sh 2> /tmp/cp-install.err
$AMI_SBIN/cp-deploy.sh 2> /tmp/cp-deploy.err




