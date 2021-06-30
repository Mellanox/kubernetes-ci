#!/bin/bash

source ./common/clean_common.sh
source ./common/sriov_operator_test.sh

export WORKSPACE=${WORKSPACE:-/tmp/k8s_$$}
export LOGDIR=$WORKSPACE/logs
export ARTIFACTS=$WORKSPACE/artifacts

export KUBECONFIG=${KUBECONFIG:-/etc/kubernetes/admin.conf}

function exit_code {
    rc="$1"
    echo "All logs $LOGDIR"
    echo "All confs $ARTIFACTS"
    echo "To stop K8S run # WORKSPACE=${WORKSPACE} ./sriov_network_operator/sriov_network_operator_ci_stop.sh"
    exit $rc
}

function main {
    status=0

    echo "all tests succeeded!!"

    test_sriov_operator_e2e
    let status=$status+$?
    if [ "$status" != 0 ]; then
        echo "Error: error testing SRIOV-operator!"
        exit_code $status
    fi

    exit_code $status
}

main

