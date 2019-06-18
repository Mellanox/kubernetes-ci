#!/bin/bash

export LOGDIR=$WORKSPACE_K8S/logs
export ARTIFACTS=$WORKSPACE_K8S/artifacts

kill $(ps -ef |grep local-up-cluster.sh|grep $WORKSPACE_K8S|awk '{print $2}')

cp /tmp/kube*.log $LOGDIR
echo "All logs $LOGDIR"
echo "All confs $ARTIFACTS"
