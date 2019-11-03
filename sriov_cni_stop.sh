#!/bin/bash

export LOGDIR=$WORKSPACE/logs
export ARTIFACTS=$WORKSPACE/artifacts

for ds in $(kubectl -n kube-system get ds |grep kube|awk '{print $1}'); do
    kubectl -n kube-system delete ds $ds
done

for sc in $(screen -ls|grep multus|awk '{print $1}'); do
    screen -X -S $sc quit
done

kill $(ps -ef |grep local-up-cluster.sh|grep $WORKSPACE|awk '{print $2}')
kill $(pgrep sriovdp)
kill $(ps -ef |grep kube |awk '{print $2}')
kill -9 $(ps -ef |grep etcd|grep http|awk '{print $2}')
ps -ef |egrep "kube|local-up-cluster|etcd"

[ -d /var/lib/cni/sriov ] && rm -rf /var/lib/cni/sriov/*

cp /tmp/kube*.log $LOGDIR
echo "All logs $LOGDIR"
echo "All confs $ARTIFACTS"
