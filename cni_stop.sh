#!/bin/bash -x

#TODO move to a common script

export LOGDIR=$WORKSPACE/logs
export ARTIFACTS=$WORKSPACE/artifacts

export KUBECONFIG=${KUBECONFIG:-/etc/kubernetes/admin.conf}

mkdir -p $WORKSPACE
mkdir -p $LOGDIR
mkdir -p $ARTIFACTS

source ./clean_common.sh

function main {

    delete_pods

    general_cleaning

    reset_vfs_guids
    
    cp /tmp/kube*.log $LOGDIR
    echo "All logs $LOGDIR"
    echo "All confs $ARTIFACTS"

}

main
