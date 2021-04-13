#!/bin/bash

export WORKSPACE=${WORKSPACE:-/tmp/k8s_$$}
export LOGDIR=$WORKSPACE/logs
export ARTIFACTS=$WORKSPACE/artifacts

export KUBECONFIG='/root/.kube/config'

function exit_code {
    rc="$1"
    echo "All logs $LOGDIR"
    echo "All confs $ARTIFACTS"
    echo "To stop K8S run # WORKSPACE=${WORKSPACE} ./sriov_network_operator/sriov_network_operator_ci_stop.sh"
    exit $rc
}

function main {
    status=0

    pushd $WORKSPACE/sriov-network-operator 

    make test-e2e-k8s
    let status=status+$?
    if [ "$status" != 0 ]; then
        echo "Error: error in e2e testing!"
        popd
        exit_code $status
    fi
    
    echo "all tests succeeded!!"
    
    popd
    exit_code $status
}

main

