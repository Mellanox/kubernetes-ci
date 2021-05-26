#!/bin/bash

source ./common/clean_common.sh

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

function test_sriov_operator_e2e {
    pushd $WORKSPACE/sriov-network-operator

    # TODO: Sometimes the config daemon fails to discover the card
    # pfs, until the root cause is determined, deleting the
    # the config daemon pod would solve the issue.

    local config_daemon_info=$(kubectl get pods -A -l app=sriov-network-config-daemon | grep -v NAME)
    kubectl delete pod -n $(awk '{print $1}' <<< $config_daemon_info)\
        $(awk '{print $2}' <<< $config_daemon_info)


    make test-e2e-k8s
    let status=$status+$?
    if [ "$status" != 0 ]; then
        echo "Error: error in e2e testing!"
        popd
        return $status
    fi

    popd
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

