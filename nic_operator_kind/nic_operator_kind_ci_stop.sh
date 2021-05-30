#!/bin/bash 
set -x

source ./common/clean_common.sh

export LOGDIR=$WORKSPACE/logs
export ARTIFACTS=$WORKSPACE/artifacts

export KUBECONFIG=${KUBECONFIG:-"/root/.kube/config"}

function main {
    mkdir -p $WORKSPACE
    mkdir -p $LOGDIR
    mkdir -p $ARTIFACTS

    delete_pods

    collect_pods_logs

    delete_nic_operator

    undeploy_gpu_operator

    sudo systemctl stop vf-switcher

    sudo rm -rf /etc/systemd/system/vf-switcher.service

    sudo rm -rf /var/run/netns/sriov-network-operator*

    sudo systemctl daemon-reload

    sudo rm -rf /etc/vf-switcher

    stop_kind_cluster "nic-operator-kind"

    general_cleaning
 
    load_core_drivers                                                                                                                                                                                                                            
    cp /tmp/kube*.log $LOGDIR
    echo "All logs $LOGDIR"
    echo "All confs $ARTIFACTS"
}

main

