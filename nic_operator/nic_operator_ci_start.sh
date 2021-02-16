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

export KUBECONFIG=${KUBECONFIG:-/etc/kubernetes/admin.conf}

export KERNEL_VERSION=${KERNEL_VERSION:-$(uname -r)}
export OS_DISTRO=${OS_DISTRO:-ubuntu}
export OS_VERSION=${OS_VERSION:-20.04}

function download_and_build {
    status=0
    if [ "$RECLONE" != true ] ; then
        return $status
    fi

    [ -d /var/lib/cni/sriov ] && rm -rf /var/lib/cni/sriov/*

    build_nic_operator_image
    return $?
}

function configure_namespace {
    local namespace=$1

    echo "Configuring namespace to be $namespace"
    pushd $WORKSPACE/mellanox-network-operator/deploy

    replace_placeholder REPLACE_NAMESPACE $namespace operator-ns.yaml
    replace_placeholder REPLACE_NAMESPACE $namespace operator.yaml
    replace_placeholder REPLACE_NAMESPACE $namespace role.yaml
    replace_placeholder REPLACE_NAMESPACE $namespace role_binding.yaml
    replace_placeholder REPLACE_NAMESPACE $namespace service_account.yaml
    replace_placeholder REPLACE_NAMESPACE $namespace crds/mellanox.com_v1alpha1_nicclusterpolicy_cr.yaml

    popd

}

function deploy_operator_components {
    let status=0

    if [[ ! -d $WORKSPACE/mellanox-network-operator/config ]];then
    
        configure_namespace "$(get_nic_operator_namespace)"
    
        pushd $WORKSPACE/mellanox-network-operator/deploy
    
        yaml_write spec.template.spec.containers[0].image 'mellanox/network-operator' operator.yaml
        let status=status+$?
    
        yaml_write spec.template.spec.containers[0].imagePullPolicy 'IfNotPresent' operator.yaml
        let status=status+$?
    
        kubectl create -f operator-resources-ns.yaml
        let status=status+$?
    
        kubectl create -f operator-ns.yaml
        let status=status+$?
    
        kubectl create -f service_account.yaml
        let status=status+$?
    
        kubectl create -f role.yaml
        let status=status+$?
    
        kubectl create -f role_binding.yaml
        let status=status+$?
    
        for file in $(find ./crds/ -type f -name *_crd.yaml);do
            kubectl apply -f "$file"
            let status=status+$?
            sleep 2
        done
    
        kubectl create -f operator.yaml
        let status=status+$?
    else
        pushd $WORKSPACE/mellanox-network-operator

        make deploy
        let status=status+$?
    fi

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

function label_node {
    node=$(kubectl get nodes -o name | cut -d/ -f2)
    kubectl label nodes $node feature.node.kubernetes.io/kernel-version.full="$KERNEL_VERSION"
    kubectl label nodes $node feature.node.kubernetes.io/pci-15b3.present=true
    kubectl label nodes $node feature.node.kubernetes.io/system-os_release.ID="$OS_DISTRO"
    kubectl label nodes $node feature.node.kubernetes.io/system-os_release.VERSION_ID="$OS_VERSION"
}

function patch_pod_cider_to_node {
    node=$(kubectl get nodes -o name | cut -d/ -f2)
    kubectl patch node "$node" -p '{"spec":{"podCIDR":"192.168.0.0/16"}}'
}

function main {
    create_workspace

    cp ./deploy/macvlan-net.yaml "$ARTIFACTS"/
    cp ./nic_operator/yaml/* "$ARTIFACTS"/

    pushd $WORKSPACE

    deploy_k8s_bare
    if [ $? -ne 0 ]; then
        echo "Failed to deploy k8s!"
        exit 1
    fi

    label_node

    deploy_calico
    if [ $? -ne 0 ]; then
        echo "Failed to deploy the calico cni"
        exit 1
    fi

    deploy_multus
    if [ $? -ne 0 ]; then
        echo "Failed to deploy the multus cni"
        exit 1
    fi

    create_macvlan_net
    if [ $? -ne 0 ]; then
        echo "Failed to create the macvlan net"
        exit 1
    fi

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

    echo "All code in $WORKSPACE"
    echo "All logs $LOGDIR"
    echo "All confs $ARTIFACTS"

    echo "Setup is up and running. Run following to start tests:"
    echo "# WORKSPACE=$WORKSPACE ./nic_operator/nic_operator_ci_test.sh"

    popd
}

main
exit $?
