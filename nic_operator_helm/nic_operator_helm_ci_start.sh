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

export SRIOV_INTERFACE=${SRIOV_INTERFACE:-auto_detect}

function download_and_build {
    status=0
    if [ "$RECLONE" != true ] ; then
        return $status
    fi

    [ -d /var/lib/cni/sriov ] && rm -rf /var/lib/cni/sriov/*

    build_nic_operator_image
    let status=$status+$?

    pull_network_operator_images
    let status=$status+$?

    set_network_operator_images_variables

    return $status
}

function configure_helm_values {
    local file_name=${1:-"${ARTIFACTS}/helm-values.yaml"}

    rm -f $file_name
    touch $file_name

    yaml_write "nfd.enabled" "true" $file_name
    yaml_write "operator.tag" "latest" $file_name
    yq d -i $file_name "operator.nodeSelector"
    yaml_write "deployCR" "true" $file_name
    

    yaml_write "ofedDriver.deploy" "true" $file_name
    yaml_write "ofedDriver.image" "$OFED_DRIVER_IMAGE" $file_name
    yaml_write "ofedDriver.repository" "$OFED_DRIVER_REPO" $file_name
    yaml_write "ofedDriver.version" "$OFED_DRIVER_VERSION" $file_name

    yaml_write "nvPeerDriver.deploy" "false" $file_name

    local rdma_shared_device_plugin_key='devicePlugin'

    if [[ -z "$(yaml_read spec.$rdma_shared_device_plugin_key $nic_operator_dir/example/crs/mellanox.com_v1alpha1_nicclusterpolicy_cr.yaml)" ]];then
        local rdma_shared_device_plugin_key='rdmaSharedDevicePlugin'
    fi

    yaml_write "$rdma_shared_device_plugin_key".deploy "true" $file_name
    yaml_write "$rdma_shared_device_plugin_key".image "$RDMA_SHARED_DEVICE_PLUGIN_IMAGE" $file_name
    yaml_write "$rdma_shared_device_plugin_key".repository "$RDMA_SHARED_DEVICE_PLUGIN_REPO" $file_name
    yaml_write "$rdma_shared_device_plugin_key".version "$RDMA_SHARED_DEVICE_PLUGIN_VERSION" $file_name

    yaml_write "$rdma_shared_device_plugin_key".resources[0].name "rdma_shared_devices_a" $file_name
    yaml_write "$rdma_shared_device_plugin_key".resources[0].ifNames[0] "$SRIOV_INTERFACE" $file_name

    yaml_write "secondaryNetwork.deploy" "true" $file_name

    yaml_write "secondaryNetwork.cniPlugins.deploy" "true" $file_name
    yaml_write "secondaryNetwork.cniPlugins.image" "$SECONDARY_NETWORK_CNI_PLUGINS_IMAGE" $file_name
    yaml_write "secondaryNetwork.cniPlugins.repository" "$SECONDARY_NETWORK_CNI_PLUGINS_REPO" $file_name
    yaml_write "secondaryNetwork.cniPlugins.version" "$SECONDARY_NETWORK_CNI_PLUGINS_VERSION" $file_name

    yaml_write "secondaryNetwork.multus.deploy" "true" $file_name
    yaml_write "secondaryNetwork.multus.image" "$SECONDARY_NETWORK_MULTUS_IMAGE" $file_name
    yaml_write "secondaryNetwork.multus.repository" "$SECONDARY_NETWORK_MULTUS_REPO" $file_name
    yaml_write "secondaryNetwork.multus.version" "$SECONDARY_NETWORK_MULTUS_VERSION" $file_name

    yaml_write "secondaryNetwork.ipamPlugin.deploy" "true" $file_name
    yaml_write "secondaryNetwork.ipamPlugin.image" "$SECONDARY_NETWORK_IPAM_PLUGIN_IMAGE" $file_name
    yaml_write "secondaryNetwork.ipamPlugin.repository" "$SECONDARY_NETWORK_IPAM_PLUGIN_REPO" $file_name
    yaml_write "secondaryNetwork.ipamPlugin.version" "$SECONDARY_NETWORK_IPAM_PLUGIN_VERSION" $file_name
}

function deploy_operator {
    let status=0

    local values_file=${1:-"${ARTIFACTS}/helm-values.yaml"}

    pushd $WORKSPACE/mellanox-network-operator

    sudo apt-get purge -y rdma-core

    helm install -f $values_file \
        -n $(get_nic_operator_namespace) \
        --create-namespace \
        ${NIC_OPERATOR_HELM_NAME} \
        ./deployment/network-operator/

    wait_nic_policy_states "" "state-ofed"
    if [ "$?" != 0 ]; then
        echo "Timed out waiting for operator to become running"
        popd
        return $status
    fi

    sleep 30
    popd
}

function main {
    create_workspace

    load_core_drivers
    rm -f /etc/cni/net.d/00*

    if [ $SRIOV_INTERFACE == 'auto_detect' ]; then
        SRIOV_INTERFACE=$(get_auto_net_device)
        export SRIOV_INTERFACE
    fi

    pushd $WORKSPACE

    deploy_k8s_bare
    if [ $? -ne 0 ]; then
        echo "Failed to deploy k8s!"
        exit 1
    fi

    deploy_calico
    if [ $? -ne 0 ]; then
        echo "Failed to deploy the calico cni"
        exit 1
    fi

    download_and_build
    if [ $? -ne 0 ]; then
        echo "Failed to download and build components"
        exit 1
    fi

    configure_helm_values
    if [ $? -ne 0 ]; then
        echo "Failed to configure helm values!"
        exit 1
    fi

    deploy_operator
    if [ $? -ne 0 ]; then
        echo "Failed to run the operator components"
        exit 1
    fi

    sleep 30

    unlabel_master

    echo "All code in $WORKSPACE"
    echo "All logs $LOGDIR"
    echo "All confs $ARTIFACTS"

    echo "Setup is up and running. Run following to start tests:"
    echo "# WORKSPACE=$WORKSPACE ./nic_operator_helm/nic_operator_helm_ci_test.sh"

    popd
}

main
exit $?
