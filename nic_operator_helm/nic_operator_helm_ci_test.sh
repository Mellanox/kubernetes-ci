#!/bin/bash

export WORKSPACE=${WORKSPACE:-/tmp/k8s_$$}
export LOGDIR=$WORKSPACE/logs
export ARTIFACTS=$WORKSPACE/artifacts

export GOROOT=${GOROOT:-/usr/local/go}
export GOPATH=${WORKSPACE}
export PATH=/usr/local/go/bin/:$GOPATH/src/k8s.io/kubernetes/third_party/etcd:$PATH
export TIMEOUT=${TIMEOUT:-300}

export POLL_INTERVAL=${POLL_INTERVAL:-10}

export KUBECONFIG=${KUBECONFIG:-/etc/kubernetes/admin.conf}

export SRIOV_INTERFACE=${SRIOV_INTERFACE:-auto_detect}

source ./common/common_functions.sh
source ./common/clean_common.sh
source ./common/nic_operator_common.sh

function exit_code {
    echo "All logs $LOGDIR"
    echo "All confs $ARTIFACTS"
    echo "To stop K8S run # WORKSPACE=${WORKSPACE} ./nic_operator_helm/nic_operator_helm_ci_stop.sh"
    exit $status
}

function test_ofed_and_rdma {
    status=0

    test_ofed_drivers
    let status=status+$?
    if [ "$status" != 0 ]; then
        echo "Error: Ofed modules failed!"
        return $status
    fi

    test_rdma_plugin "" "example-macvlan"
    let status=status+$?
    if [ "$status" != 0 ]; then
        echo "Error: RDMA device plugin testing Failed!"
        return $status
    fi
}

function main {

    status=0

    mkdir -p $WORKSPACE
    mkdir -p $LOGDIR
    mkdir -p $ARTIFACTS
    
    pushd $WORKSPACE

    local macvlan_sample_file="$ARTIFACTS"/example-macvlan-cr.yaml

    configure_macvlan_custom_resource "$macvlan_sample_file"
    kubectl create -f "$macvlan_sample_file"

    test_ofed_and_rdma
    let status=status+$?
    if [ "$status" != 0 ]; then
        echo "Error: Testing deploying OFED and RDMA shared device plugin failed!!"
        exit_code $status
    fi

    popd

    echo ""
    echo "All test succeeded!!"
    echo ""
}

main
exit_code $status

