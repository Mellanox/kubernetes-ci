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

export SRIOV_NETWORK_OPERATOR_REPO=${SRIOV_NETWORK_OPERATOR_REPO:-https://github.com/k8snetworkplumbingwg/sriov-network-operator.git}
export SRIOV_NETWORK_OPERATOR_BRANCH=${SRIOV_NETWORK_OPERATOR_BRANCH:-'master'}
export SRIOV_NETWORK_OPERATOR_PR=${SRIOV_NETWORK_OPERATOR_PR:-''}

export SRIOV_INTERFACE=${SRIOV_INTERFACE:-auto_detect}

sriov_operator_project_file=$WORKSPACE/sriov-network-operator

export project="nic-operator-helm"

source ./common/common_functions.sh
source ./common/clean_common.sh
source ./common/nic_operator_common.sh
source ./common/nic_operator_test.sh
source ./common/sriov_operator_test.sh

function exit_code {
    echo "All logs $LOGDIR"
    echo "All confs $ARTIFACTS"
    echo "To stop K8S run # WORKSPACE=${WORKSPACE} ./nic_operator_helm/nic_operator_helm_ci_stop.sh"
    exit $status
}

function test_sriov_operator_rping {
    local sriov_operator_namespace=$(get_nic_operator_namespace)

    local policy_name="example-sriov-policy"
    local network_name="example-sriov-network"
    local resource_name="mlnxnics"

    create_sriov_node_policy "$policy_name" "$sriov_operator_namespace" "$resource_name"
    let status=$status+$?
    if [ "$status" != 0 ]; then
        echo "Error: Failed to create the sriovnetworknodepolicy!!"
        return $status
    fi

    create_sriov_network "$network_name" "$sriov_operator_namespace" "$resource_name"
    let status=$status+$?
    if [ "$status" != 0 ]; then
        echo "Error: Failed to create the sriovnetwork!!"
        return $status
    fi

    test_rdma_plugin "" "$network_name" "nvidia.com/${resource_name}"
    let status=$status+$?
    if [ "$status" != 0 ]; then
        echo "Error: Failed to test rping between two sriov pods!!"
        return $status
    fi

    delete_sriov_node_policy "$policy_name" "$sriov_operator_namespace"
    let status=$status+$?
    if [ "$status" != 0 ]; then
        echo "Error: Failed to delete the sriovnetworknodepolicy!!"
        return $status
    fi

    return 0
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

    test_ofed_drivers
    let status=$status+$?
    if [ "$status" != 0 ]; then
        echo "Error: Testing deploying OFED failed!!"
        exit_code $status
    fi

    test_sriov_operator_rping
    let status=$status+$?
    if [ "$status" != 0 ]; then
        echo "Error: Testing SRIOV network operator E2E tests failed!!"
        exit_code $status
    fi

    popd

    echo ""
    echo "All test succeeded!!"
    echo ""
}

main
exit_code $?

