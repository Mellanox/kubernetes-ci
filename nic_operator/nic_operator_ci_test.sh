#!/bin/bash

export WORKSPACE=${WORKSPACE:-/tmp/k8s_$$}
export LOGDIR=$WORKSPACE/logs
export ARTIFACTS=$WORKSPACE/artifacts

export GOROOT=${GOROOT:-/usr/local/go}
export GOPATH=${WORKSPACE}
export PATH=/usr/local/go/bin/:$GOPATH/src/k8s.io/kubernetes/third_party/etcd:$PATH
export TIMEOUT=${TIMEOUT:-600}

export POLL_INTERVAL=${POLL_INTERVAL:-10}

export KUBECONFIG=${KUBECONFIG:-/etc/kubernetes/admin.conf}

export SRIOV_INTERFACE=${SRIOV_INTERFACE:-auto_detect}

export NIC_CLUSTER_POLICY_DEFAULT_NAME='nic-cluster-policy'
export MACVLAN_NETWORK_DEFAULT_NAME='example-macvlan'

export CNI_BIN_DIR=${CNI_BIN_DIR:-'/opt/cni/bin'}

source ./common/common_functions.sh
source ./common/clean_common.sh
source ./common/nic_operator_common.sh
source ./common/nic_operator_test.sh

test_pod_image='harbor.mellanox.com/cloud-orchestration/rping-test'

function exit_code {
    rc="$1"
    echo "All logs $LOGDIR"
    echo "All confs $ARTIFACTS"
    echo "To stop K8S run # WORKSPACE=${WORKSPACE} ./nic_operator/nic_operator_ci_stop.sh"
    exit $status
}

function main {

    status=0
    
    mkdir -p $WORKSPACE
    mkdir -p $LOGDIR
    mkdir -p $ARTIFACTS
    
    pushd $WORKSPACE

    load_core_drivers

    if [ $SRIOV_INTERFACE == 'auto_detect' ]; then
        export SRIOV_INTERFACE=$(ls -l /sys/class/net/ | grep $(lspci |grep Mellanox | grep -Ev 'MT27500|MT27520' | head -n1 | awk '{print $1}') | awk '{print $9}')
    fi

    if [[ "${RDMA_RESOURCE}" == "auto_detect" ]];then
        export RDMA_RESOURCE=$(get_interface_rdma_resource_name)
    fi

    set_network_operator_images_variables

    test_rdma_only
    let status=status+$?
    if [ "$status" != 0 ]; then
        echo "Error: Testing deploying RDMA shared device plugin failed!!"
        exit_code $status
    fi


    test_ofed_and_rdma
    let status=status+$?
    if [ "$status" != 0 ]; then
        echo "Error: Testing deploying OFED and RDMA shared device plugin failed!!"
        exit_code $status
    fi

    test_ofed_and_host_device_ib
    let status=$status+$?
    if [[ "$status" != "0" ]]; then
        echo "Error: Test deploying OFED and infiniband host device failed!!"
        exit_code $status
    fi

    test_nv_peer_mem
    let status=status+$?
    if [ "$status" != 0 ]; then
        echo "Error: Testing deploying OFED, RDMA, and nv-peer-mem failed!!"
        exit_code $status
    fi

    test_nv_peer_mem_with_host_device
    let status=$status+$?
    if [[ "$status" != "0" ]]; then
        echo "Error: Test deploying OFED and host device failed!!"
        exit_code $status
    fi

    popd
    
    echo ""
    echo "All test succeeded!!"
    echo ""
}

main
exit_code $status

