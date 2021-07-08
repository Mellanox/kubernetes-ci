#!/bin/bash

source ./common/common_functions.sh
source ./common/clean_common.sh
source ./common/nic_operator_common.sh
source ./common/nic_operator_test.sh

export WORKSPACE=${WORKSPACE:-/tmp/k8s_$$}
export LOGDIR=$WORKSPACE/logs
export ARTIFACTS=$WORKSPACE/artifacts

export GOROOT=${GOROOT:-/usr/local/go}
export GOPATH=${WORKSPACE}
export PATH=/usr/local/go/bin/:$GOPATH/src/k8s.io/kubernetes/third_party/etcd:$PATH
export TIMEOUT=${TIMEOUT:-600}

export POLL_INTERVAL=${POLL_INTERVAL:-10}

export KUBECONFIG=${KUBECONFIG:-"/root/.kube/config"}

export SRIOV_INTERFACE=${SRIOV_INTERFACE:-auto_detect}

export NIC_CLUSTER_POLICY_DEFAULT_NAME='nic-cluster-policy'
export MACVLAN_NETWORK_DEFAULT_NAME='example-macvlan'

export CNI_BIN_DIR=${CNI_BIN_DIR:-'/opt/cni/bin'}

test_pod_image='harbor.mellanox.com/cloud-orchestration/rping-test'

project="nic-operator-kind"

function exit_code {
    rc="$1"
    echo "All logs $LOGDIR"
    echo "All confs $ARTIFACTS"
    echo "To stop K8S run # WORKSPACE=${WORKSPACE} ./nic_operator_kind/nic_operator_kind_ci_stop.sh"
    exit $status
}

function main {

    status=0
    
    mkdir -p $WORKSPACE
    mkdir -p $LOGDIR
    mkdir -p $ARTIFACTS
    
    pushd $WORKSPACE

    load_core_drivers

    sudo systemctl stop opensm

    export SRIOV_INTERFACE=$(read_netdev_from_vf_switcher_confs)

    set_network_operator_images_variables

    test_ofed_only
    let status=status+$?
    if [ "$status" != 0 ]; then
        echo "Error: Testing deploying the OFED only failed!!"
        exit_code $status
    fi
    
    sleep 10

    test_host_device
    let status=$status+$?
    if [[ "$status" != "0" ]]; then
        echo "Error: Test deploying the host device failed!!"
        exit_code $status
    fi

    test_ofed_and_host_device
    let status=$status+$?
    if [[ "$status" != "0" ]]; then
        echo "Error: Test deploying OFED and host device failed!!"
        exit_code $status
    fi

    test_host_device_ib
    let status=$status+$?
    if [[ "$status" != "0" ]]; then
        echo "Error: Test deploying the infiniband host device failed!!"
        exit_code $status
    fi

    test_probes
    let status=status+$?
    if [ "$status" != 0 ]; then
        echo "Error: Probes test failed!"
        exit_code $status
    fi

    test_secondary_network
    let status=status+$?
    if [ "$status" != 0 ]; then
        echo "Error: Testing secondary network failed!!"
        exit_code $status
    fi

    test_predefined_name
    let status=status+$?
    if [ "$status" != 0 ]; then
        echo "Error: Predefined name test failed!"
        exit_code $status
    fi

    test_deleting_network_operator
    let status=status+$?
    if [ "$status" != 0 ]; then
        echo "Error: Test Deleting Network Operator failed!"
        exit_code $status
    fi

    popd
    
    echo ""
    echo "All test succeeded!!"
    echo ""
}

main
exit_code $status

