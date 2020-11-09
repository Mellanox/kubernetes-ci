#!/bin/bash 
set -x

export LOGDIR=$WORKSPACE/logs
export ARTIFACTS=$WORKSPACE/artifacts

export KUBECONFIG=${KUBECONFIG:-/etc/kubernetes/admin.conf}

source ./common/clean_common.sh
source ./common/nic_operator_common.sh

function delete_nic_operator_via_helm {
    helm uninstall -n "${NIC_OPERATOR_NAMESPACE}" "$NIC_OPERATOR_HELM_NAME"
    asure_resource_deleted 'pod' "${NIC_OPERATOR_NAMESPACE}"
    let status=status+$?
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

    delete_nic_operator_via_helm

    general_cleaning
 
    load_core_drivers                                                                                                                                                                                                                            
    cp /tmp/kube*.log $LOGDIR
    echo "All logs $LOGDIR"
    echo "All confs $ARTIFACTS"
}

main

