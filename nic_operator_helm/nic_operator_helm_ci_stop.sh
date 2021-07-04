#!/bin/bash 
set -x

export LOGDIR=$WORKSPACE/logs
export ARTIFACTS=$WORKSPACE/artifacts

export KUBECONFIG=${KUBECONFIG:-/etc/kubernetes/admin.conf}

export project="nic-operator-helm"

source ./common/clean_common.sh
source ./common/nic_operator_common.sh

function delete_nic_operator_via_helm {
    helm uninstall -n "$(get_nic_operator_namespace)" "$NIC_OPERATOR_HELM_NAME"
    asure_resource_deleted 'pod' "$(get_nic_operator_namespace)"
    let status=$status+$?
    if [[ "$status" != "0" ]];then
        echo "Failed to delete the nic operator using helm!!"
        return 1
    fi
}

function main {
    mkdir -p $WORKSPACE
    mkdir -p $LOGDIR
    mkdir -p $ARTIFACTS

    delete_pods
    
    collect_pods_logs

    collect_nodes_info

    delete_nic_operator_via_helm

    general_cleaning

    stop_kind_cluster "${project}"
 
    load_core_drivers                                                                                                                                                                                                                            
    cp /tmp/kube*.log $LOGDIR
    echo "All logs $LOGDIR"
    echo "All confs $ARTIFACTS"
}

main

