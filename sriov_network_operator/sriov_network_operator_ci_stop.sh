#!/bin/bash -x

source ./common/clean_common.sh

export LOGDIR=$WORKSPACE/logs
export ARTIFACTS=$WORKSPACE/artifacts

export KUBECONFIG=${KUBECONFIG:-/etc/kubernetes/admin.conf}

function clean_antrea_runtime {
    rm -rf /var/run/antrea/
}

function main {
    mkdir -p $WORKSPACE
    mkdir -p $LOGDIR
    mkdir -p $ARTIFACTS

    delete_pods

    collect_pods_logs

    collect_nodes_info

    collect_vf_switcher_logs

    sudo systemctl stop vf-switcher

    sudo rm -rf /etc/systemd/system/vf-switcher.service

    sudo rm -rf /var/run/netns/sriov-network-operator*

    sudo systemctl daemon-reload

    sudo rm -rf /etc/vf-switcher

    stop_kind_cluster "sriov-network-operator"

    general_cleaning

    cp /tmp/kube*.log $LOGDIR
    echo "All logs $LOGDIR"
    echo "All confs $ARTIFACTS"

}

main
