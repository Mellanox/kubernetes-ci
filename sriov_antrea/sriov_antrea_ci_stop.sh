#!/bin/bash -x

export LOGDIR=$WORKSPACE/logs
export ARTIFACTS=$WORKSPACE/artifacts

export KUBECONFIG=${KUBECONFIG:-/etc/kubernetes/admin.conf}

source ./common/clean_common.sh

function main {
    mkdir -p $WORKSPACE
    mkdir -p $LOGDIR
    mkdir -p $ARTIFACTS

    delete_pods

    general_cleaning
    
    cp /tmp/kube*.log $LOGDIR
    echo "All logs $LOGDIR"
    echo "All confs $ARTIFACTS"

}

main
