#!/bin/bash -x

source ./common/common_functions.sh

export RECLONE=${RECLONE:-true}
export WORKSPACE=${WORKSPACE:-/tmp/k8s_$$}
export LOGDIR=$WORKSPACE/logs
export ARTIFACTS=$WORKSPACE/artifacts
export TIMEOUT=${TIMEOUT:-300}
export POLL_INTERVAL=${POLL_INTERVAL:-10}

export SRIOV_NETWORK_OPERATOR_REPO=${SRIOV_NETWORK_OPERATOR_REPO:-https://github.com/k8snetworkplumbingwg/sriov-network-operator.git}
export SRIOV_NETWORK_OPERATOR_BRANCH=${SRIOV_NETWORK_OPERATOR_BRANCH:-''}
export SRIOV_NETWORK_OPERATOR_PR=${SRIOV_NETWORK_OPERATOR_PR:-'97'}
export SRIOV_NETWORK_OPERATOR_HARBOR_IMAGE=''

export SRIOV_CNI_IMAGE='nfvpe/sriov-cni:v2.6'
export SRIOV_INFINIBAND_CNI_IMAGE='mellanox/ib-sriov-cni:faa9e36'
export SRIOV_DEVICE_PLUGIN_IMAGE='quay.io/openshift/origin-sriov-network-device-plugin:4.8'
export SRIOV_NETWORK_CONFIG_DAEMON_IMAGE='mellanox/sriov-operator-daemon:ci'
export SRIOV_NETWORK_OPERATOR_IMAGE='mellanox/sriov-operator:ci'

export GOPATH=${WORKSPACE}
export PATH=/usr/local/go/bin/:$GOPATH/src/k8s.io/kubernetes/third_party/etcd:$PATH

export CNI_BIN_DIR=${CNI_BIN_DIR:-/opt/cni/bin/}
export CNI_CONF_DIR=${CNI_CONF_DIR:-/etc/cni/net.d/}
export KUBECONFIG=${KUBECONFIG:-/etc/kubernetes/admin.conf}

#TODO add autodiscovering
export SRIOV_INTERFACE=${SRIOV_INTERFACE:-auto_detect}
export VFS_NUM=${VFS_NUM:-4}

project=sriov-network-operator

function download_and_build {
    status=0
    if [ "$RECLONE" != true ] ; then
        return $status
    fi

    export DOCKERFILE=Dockerfile
    export IMAGE_TAG="$SRIOV_NETWORK_OPERATOR_IMAGE"
    build_github_project "$project" "make image"
    let status=status+$?
    if [ "$status" != 0 ]; then
        echo "ERROR: Failed to build network operator iamge: $SRIOV_NETWORK_OPERATOR_IMAGE!"
        return $status
    fi 

    upload_image_to_kind "$SRIOV_NETWORK_OPERATOR_IMAGE" "$project"
    let status=status+$?
    if [[ "$status" != "0" ]];then
        echo "ERROR: Failed to upload iamge $SRIOV_NETWORK_OPERATOR_IMAGE! to kind!"
        return $status
    fi

    export DOCKERFILE=Dockerfile.sriov-network-config-daemon
    export IMAGE_TAG="$SRIOV_NETWORK_CONFIG_DAEMON_IMAGE"
    build_github_project "$project" "make image"
    let status=status+$?
    if [ "$status" != 0 ]; then
        echo "ERROR: Failed to build network operator config-daemon iamge: $SRIOV_NETWORK_CONFIG_DAEMON_IMAGE!"
        return $status
    fi

    upload_image_to_kind "$SRIOV_NETWORK_CONFIG_DAEMON_IMAGE" "$project"
    let status=status+$?
    if [[ "$status" != "0" ]];then
        echo "ERROR: Failed to upload iamge $SRIOV_NETWORK_CONFIG_DAEMON_IMAGE! to kind!"
        return $status
    fi
    
    return $status
}

function deploy_sriov_network_operator {
    local status=0

    pushd "$WORKSPACE/sriov-network-operator"

    label_node

    make deploy-setup-k8s
    let status=$status+$?
    if [[ $status != "0" ]];then
        echo "Error: Failed to deploy the network operator!"
        popd
        return $status
    fi

    wait_pod_state 'sriov-network-config-daemon' 'Running'
    let status=$status+$?
    if [[ $status != "0" ]];then
        echo "Error: Timeout waiting for sriov-network-config-daemon to be up!"
        popd
        return $status
    fi

    popd
}

function label_node {
    kubectl label nodes ${project}-worker node-role.kubernetes.io/worker=""
    kubectl label nodes ${project}-worker feature.node.kubernetes.io/network-sriov.capable="true"
}

function main {

    create_workspace

    deploy_kind_cluster_with_multus "$project" "1"
    if [ $? -ne 0 ]; then
        echo "Failed to deploy k8s"
        popd
        return 1
    fi

    pushd $WORKSPACE
    
    download_and_build
    if [ $? -ne 0 ]; then
        echo "Failed to download and build components"
        popd
        return 1
    fi

    deploy_sriov_network_operator
    if [ $? -ne 0 ]; then
        echo "Failed to deploy the sriov-network-operator!"
        popd
        return 1
    fi
    
    echo "All code in $WORKSPACE"
    echo "All logs $LOGDIR"
    echo "All confs $ARTIFACTS"
    
    echo "Setup is up and running. Run following to start tests:"
    echo "# WORKSPACE=$WORKSPACE NETWORK=$NETWORK ./sriov_network_operator/sriov_network_operator_ci_test.sh"
    popd

}

main
exit $?
