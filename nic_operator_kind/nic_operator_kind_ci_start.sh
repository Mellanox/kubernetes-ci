#!/bin/bash -x

source ./common/common_functions.sh
source ./common/nic_operator_common.sh

export RECLONE=${RECLONE:-true}
export WORKSPACE=${WORKSPACE:-/tmp/k8s_$$}
export LOGDIR=$WORKSPACE/logs
export ARTIFACTS=$WORKSPACE/artifacts
export TIMEOUT=${TIMEOUT:-300}
export POLL_INTERVAL=${POLL_INTERVAL:-10}

export GOPATH=${WORKSPACE}
export PATH=/usr/local/go/bin/:$GOPATH/src/k8s.io/kubernetes/third_party/etcd:$PATH

export KUBECONFIG=${KUBECONFIG:-"/root/.kube/config"}

export KERNEL_VERSION=${KERNEL_VERSION:-$(uname -r)}
export OS_DISTRO=${OS_DISTRO:-ubuntu}
export OS_VERSION=${OS_VERSION:-$(get_kind_distro_version)}

export KIND_NODE_IMAGE=${KIND_NODE_IMAGE:-'harbor.mellanox.com/cloud-orchestration/kind-node:latest'}

project="nic-operator-kind"

function download_and_build {
    status=0
    if [ "$RECLONE" != true ] ; then
        return $status
    fi

    [ -d /var/lib/cni/sriov ] && rm -rf /var/lib/cni/sriov/*

    build_nic_operator_image
    let status=status+$?

    upload_image_to_kind "mellanox/network-operator:latest" "${project}"

    pull_network_operator_images "${project}"
    let status=status+$?

    return $status
}

function deploy_operator_components {
    let status=0

    pushd $WORKSPACE/mellanox-network-operator

    make deploy
    let status=status+$?

    if [ "$status" != 0 ]; then
        echo "Failed to deploy operator componentes"
        return $status
    fi

    wait_pod_state "network-operator" "Running"
    if [ "$?" != 0 ]; then
        echo "Timed out waiting for operator to become running"
        return $status
    fi

    sleep 30
    popd
}

function label_worker_node {
    node=$(kubectl get nodes -o name | cut -d/ -f2 | grep worker)
    kubectl label nodes $node feature.node.kubernetes.io/kernel-version.full="$KERNEL_VERSION"
    kubectl label nodes $node feature.node.kubernetes.io/pci-15b3.present=true
    kubectl label nodes $node feature.node.kubernetes.io/system-os_release.ID="$OS_DISTRO"
    kubectl label nodes $node feature.node.kubernetes.io/system-os_release.VERSION_ID="$OS_VERSION"
}

function main {
    create_workspace

    cp ./deploy/macvlan-net.yaml "$ARTIFACTS"/

    sudo modprobe ib_ipoib

    deploy_kind_cluster "$project" "1" "2"
    if [ $? -ne 0 ]; then
        echo "Failed to deploy k8s"
        popd
        return 1
    fi

    pushd $WORKSPACE

    label_worker_node

    download_and_build
    if [ $? -ne 0 ]; then
        echo "Failed to download and build components"
        exit 1
    fi

    deploy_operator_components
    if [ $? -ne 0 ]; then
        echo "Failed to run the operator components"
        exit 1
    fi

    configure_macvlan_custom_resource "$ARTIFACTS/example-macvlan-cr.yaml"
    kubectl create -f "$ARTIFACTS/example-macvlan-cr.yaml"

    echo "All code in $WORKSPACE"
    echo "All logs $LOGDIR"
    echo "All confs $ARTIFACTS"

    echo "Setup is up and running. Run following to start tests:"
    echo "# WORKSPACE=$WORKSPACE ./nic_operator_kind/nic_operator_kind_ci_test.sh"

    popd
}

main
exit $?
