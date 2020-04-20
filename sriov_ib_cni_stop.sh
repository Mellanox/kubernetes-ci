#!/bin/bash

#TODO move to a common script

export LOGDIR=$WORKSPACE/logs
export ARTIFACTS=$WORKSPACE/artifacts

mkdir -p $WORKSPACE
mkdir -p $LOGDIR
mkdir -p $ARTIFACTS

function stop_system_daemonset {
    for ds in $(kubectl -n kube-system get ds |grep kube|awk '{print $1}'); do
        kubectl -n kube-system delete ds $ds
    done
}

function stop_k8s_screen {
    for sc in $(screen -ls|grep multus|awk '{print $1}'); do
        screen -X -S $sc quit
    done
}

function asure_all_stoped {
    kill $(ps -ef |grep local-up-cluster.sh|grep $WORKSPACE|awk '{print $2}')
    kill $(pgrep sriovdp)
    kill $(ps -ef |grep kube |awk '{print $2}')
    kill -9 $(ps -ef |grep etcd|grep http|awk '{print $2}')
}

function delete_all_docker_container {
    docker stop $(docker ps -q)
    docker rm $(docker ps -a -q)
}

function delete_all_docker_images {
    docker rmi $(docker images -q)
}

stop_system_daemonset

stop_k8s_screen

asure_all_stoped

delete_all_docker_container

delete_all_docker_images

ps -ef |egrep "kube|local-up-cluster|etcd"

[ -d /var/lib/cni/sriov ] && rm -rf /var/lib/cni/sriov/*

cp /tmp/kube*.log $LOGDIR
echo "All logs $LOGDIR"
echo "All confs $ARTIFACTS"
