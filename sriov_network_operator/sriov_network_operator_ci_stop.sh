#!/bin/bash -x

source ./common/clean_common.sh

export LOGDIR=$WORKSPACE/logs
export ARTIFACTS=$WORKSPACE/artifacts

export KUBECONFIG=${KUBECONFIG:-/etc/kubernetes/admin.conf}

function main {
    mkdir -p $WORKSPACE
    mkdir -p $LOGDIR
    mkdir -p $ARTIFACTS

    delete_pods

    collect_pods_logs

    collect_nodes_info

    collect_vf_switcher_logs

    sudo systemctl stop vf-switcher

    sudo systemctl daemon-reload

    stop_kind_cluster "sriov-network-operator"

    general_cleaning

    cp /tmp/kube*.log $LOGDIR
    echo "All logs $LOGDIR"
    echo "All confs $ARTIFACTS"

}

main
