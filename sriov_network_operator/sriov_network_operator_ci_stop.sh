#!/bin/bash -x

source ./common/clean_common.sh

export LOGDIR=$WORKSPACE/logs
export ARTIFACTS=$WORKSPACE/artifacts

export KUBECONFIG=${KUBECONFIG:-/etc/kubernetes/admin.conf}

project=sriov-network-operator

function main {
    mkdir -p $WORKSPACE
    mkdir -p $LOGDIR
    mkdir -p $ARTIFACTS

    collect_pods_logs

    collect_nodes_info

    get_sriov_node_state "${project}-worker" "sriov-network-operator"

    collect_vf_switcher_logs

    delete_pods

    sudo systemctl stop vf-switcher

    sudo systemctl daemon-reload

    stop_kind_cluster "sriov-network-operator"

    general_cleaning

    cp /tmp/kube*.log $LOGDIR
    echo "All logs $LOGDIR"
    echo "All confs $ARTIFACTS"

}

main
