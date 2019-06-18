#!/bin/bash

export LOGDIR=$WORKSPACE/logs
export ARTIFACTS=$WORKSPACE/artifacts

kill $(ps -ef |grep local-up-cluster.sh|grep $WORKSPACE|awk '{print $2}')

cp /tmp/kube*.log $LOGDIR
echo "All logs $LOGDIR"
echo "All confs $ARTIFACTS"
