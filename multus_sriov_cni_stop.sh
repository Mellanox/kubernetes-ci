#!/bin/bash

export LOGDIR=$WORKSPACE/logs
export ARTIFACTS=$WORKSPACE/artifacts

sudo kill $(ps -ef |grep local-up-cluster.sh|grep $WORKSPACE|awk '{print $2}')
sudo kill $(pgrep sriovdp)
sudo kill $(ps -ef |grep kube |awk '{print $2}')
sudo kill -9 $(ps -ef |grep etcd|grep http|awk '{print $2}')
ps -ef |egrep "kube|local-up-cluster|etcd"

cp /tmp/kube*.log $LOGDIR
echo "All logs $LOGDIR"
echo "All confs $ARTIFACTS"
