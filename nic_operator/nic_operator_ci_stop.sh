#!/bin/bash 
set -x

export LOGDIR=$WORKSPACE/logs
export ARTIFACTS=$WORKSPACE/artifacts

export KUBECONFIG=${KUBECONFIG:-/etc/kubernetes/admin.conf}

source ./common/clean_common.sh

function delete_nic_operator_namespace {
    nic_operator_namespace_file=$WORKSPACE/mellanox-network-operator/deploy/operator-ns.yaml
    kubectl delete -f $nic_operator_namespace_file
    sleep 20
}

function main {
    mkdir -p $WORKSPACE
    mkdir -p $LOGDIR
    mkdir -p $ARTIFACTS

    delete_pods
    
    delete_nic_operator_namespace

    general_cleaning
 
    load_core_drivers                                                                                                                                                                                                                            
    cp /tmp/kube*.log $LOGDIR
    echo "All logs $LOGDIR"
    echo "All confs $ARTIFACTS"
}

main

