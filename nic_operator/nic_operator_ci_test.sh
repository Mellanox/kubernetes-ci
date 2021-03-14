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

test_pod_image='harbor.mellanox.com/cloud-orchestration/rping-test'

function nic_policy_create {
    status=0
    cr_file="$1"

    kubectl create -f $cr_file

    wait_nic_policy_states "$(yq r $cr_file metadata.name)"
    let status=status+$?
    if [ "$status" != 0 ]; then
        echo "Error: error in creating $cr_file."
        return $status
    fi
    return 0
}

function test_deleting_network_operator {
    echo ""
    echo "Test Deleting Network Operator...."
    status=0

    local sample_file="$ARTIFACTS"/ofed-nic-cluster-policy.yaml

    configure_common "$sample_file"
    configure_ofed "$sample_file"

    nic_policy_create "$sample_file"
    let status=status+$?
    if [ "$status" != 0 ]; then
        echo "Error: error in creating the example nic_policy."
        return $status
    fi

    sleep 10

    local ofed_module_srcversion="$(cat /sys/module/mlx5_core/srcversion)"

    delete_nic_operator

    sleep 20

    echo ""
    echo "checking mlx5_fpga_tools presence..."
    if [[ -n "$(lsmod | grep mlx5_fpga_tools)" ]];then
        echo "ERROR: mlx5_fpga_tools is still loaded in the system!!!"
        return 1
    fi

    echo ""
    echo "Checking mlx5_core srcversion... "
    sudo modprobe mlx5_core
    sleep 5
    if [[ "$(cat /sys/module/mlx5_core/srcversion)" == "$ofed_module_srcversion" ]];then
        echo "ERROR: inbox mlx5_core srcversion is the same as the OFED version!!"
        echo "Assuming OFED modules are still loaded in the system...."
        return 1
    fi

    echo ""
    echo "Test Deleting Network Operator succeeded!"
    return 0
}

function test_rdma_only {
    status=0

    sudo apt-get install -y rdma-core

    load_core_drivers
    sleep 2

    load_rdma_modules
    sleep 2

    local sample_file="$ARTIFACTS"/rdma-nic-cluster-policy.yaml

    configure_common "$sample_file"
    configure_device_plugin "$sample_file"

    nic_policy_create "$sample_file"
    let status=status+$?
    if [ "$status" != 0 ]; then
        echo "Error: error in creating the example nic_policy."
        return $status
    fi

    sleep 10

    test_rdma_plugin
    let status=status+$?
    if [ "$status" != 0 ]; then
        echo "Error: RDMA device plugin testing Failed!"
        return $status
    fi

    delete_nic_cluster_policies
    let status=status+$?
    if [ "$status" != 0 ]; then
        echo "Error: Couldn't delete $sample_file!"
        return $status
    fi
    return 0
}

function configure_common {
    local file_name="$1"
    local nic_policy_name=${2:-"$NIC_CLUSTER_POLICY_DEFAULT_NAME"}

    if [[ -f "$file_name" ]];then
        rm -f "$file_name"
    fi
    
    touch "$file_name"

    yaml_write 'apiVersion' 'mellanox.com/v1alpha1' "$file_name"
    yaml_write 'kind' 'NicClusterPolicy' "$file_name"
    yaml_write 'metadata.name' "$nic_policy_name" "$file_name"
    yaml_write 'metadata.namespace' "$(get_nic_operator_namespace)" "$file_name"
}

function configure_ofed {
    local file_name="$1"

    sudo apt-get purge -y rdma-core

    modprobe -r rpcrdma

    configure_images_specs "ofedDriver" "$file_name"
}

function configure_device_plugin {
    local file_name="$1"
    local rdma_resource_name=${2:-'rdma_shared_devices_a'}

    local rdma_shared_device_plugin_key='devicePlugin'

    if [[ -z "$(yaml_read spec.$rdma_shared_device_plugin_key $nic_operator_dir/example/crs/mellanox.com_v1alpha1_nicclusterpolicy_cr.yaml)" ]];then
        local rdma_shared_device_plugin_key='rdmaSharedDevicePlugin'
    fi

    configure_images_specs "$rdma_shared_device_plugin_key" "$file_name"

    yaml_write spec."$rdma_shared_device_plugin_key".config "\
{
  \"configList\": [{
    \"resourceName\": \"$rdma_resource_name\",
    \"rdmaHcaMax\": 1000,
    \"devices\": [\"$SRIOV_INTERFACE\"]
  }]
}
" "$file_name"
}

function configure_nv_peer_mem {
    local file_name="$1"

    configure_images_specs "nvPeerDriver" "$file_name"
    yaml_write spec.nvPeerDriver.gpuDriverSourcePath "/run/nvidia/driver"\
     "$file_name"
}

function test_ofed_only {
    status=0
    local sample_file="$ARTIFACTS"/ofed-nic-cluster-policy.yaml

    configure_common "$sample_file"
    configure_ofed "$sample_file"

    nic_policy_create "$sample_file"
    let status=status+$?
    if [ "$status" != 0 ]; then
        echo "Error: error in creating the example nic_policy."
        return $status
    fi

    sleep 10

    test_ofed_drivers
    let status=status+$?
    if [ "$status" != 0 ]; then
        echo "Error: Ofed modules failed!"
        return $status
    fi

    delete_nic_cluster_policies
    let status=status+$?
    if [ "$status" != 0 ]; then
        echo "Error: Couldn't delete ofed-nic-cluster-policy.yaml!"
        return $status
    fi
}

function test_ofed_and_rdma {
    status=0
    local sample_file="$ARTIFACTS"/ofed-rdma-nic-cluster-policy.yaml

    configure_common "$sample_file"
    configure_ofed "$sample_file"
    configure_device_plugin "$sample_file"

    nic_policy_create "$sample_file"
    let status=status+$?
    if [ "$status" != 0 ]; then
        echo "Error: error in creating the example nic_policy."
        return $status
    fi

    sleep 10

    test_ofed_drivers
    let status=status+$?
    if [ "$status" != 0 ]; then
        echo "Error: Ofed modules failed!"
        return $status
    fi

    test_rdma_plugin
    let status=status+$?
    if [ "$status" != 0 ]; then
        echo "Error: RDMA device plugin testing Failed!"
        return $status
    fi

    delete_nic_cluster_policies
    let status=status+$?
    if [ "$status" != 0 ]; then
        echo "Error: Couldn't delete ofed-rdma-nic-cluster-policy.yaml!"
        return $status
    fi
}

function test_nv_peer_mem {
    status=0

    deploy_gpu_operator
    let status=$status+$?
    if [ "$status" != 0 ]; then
        echo "Error: error in deploying the GPU operator."
        return $status
    fi

    local sample_file="$ARTIFACTS"/ofed-rdma-nv-peer-nic-cluster-policy.yaml

    configure_common "$sample_file"
    configure_ofed "$sample_file"
    configure_device_plugin "$sample_file"
    configure_nv_peer_mem "$sample_file"

    nic_policy_create "$sample_file"
    let status=status+$?
    if [ "$status" != 0 ]; then
        echo "Error: error in creating the example nic_policy."
        return $status
    fi

    sleep 10

    test_ofed_drivers
    let status=status+$?
    if [ "$status" != 0 ]; then
        echo "Error: Ofed modules failed!"
        return $status
    fi

    test_gpu_direct "harbor.mellanox.com/cloud-orchestration/cuda-perftest:Ubuntu20.04-cuda-devel-11.2.1"
    let status=status+$?
    if [ "$status" != 0 ]; then
        echo "Error: nv-peer-mem driver testing Failed!"
        return $status
    fi

    delete_nic_cluster_policies
    let status=status+$?
    if [ "$status" != 0 ]; then
        echo "Error: Couldn't delete $sample_file!"
        return $status
    fi

    undeploy_gpu_operator
    let status=status+$?
    if [ "$status" != 0 ]; then
        echo "Error: Couldn't undeploy the GPU operator!"
        return $status
    fi
}

function test_secondary_network {
    status=0
    local sample_file="$ARTIFACTS"/seconday-network-nic-cluster-policy.yaml
    local multus_file="$WORKSPACE/multus-cni/images/multus-daemonset.yml"
    local macvlan_bin="$WORKSPACE/plugins/bin/macvlan"

    echo ""
    echo "Testing Secondary networks..."

    if [[ -f "$multus_file" ]];then
        kubectl delete -f "$multus_file"
    fi

    sudo rm -f "${CNI_BIN_DIR}/macvlan"
    sudo rm -f "${CNI_BIN_DIR}/multus"
    sudo rm -f "${CNI_BIN_DIR}/whereabouts"

    if [[ -d "$WORKSPACE/mellanox-network-operator/config" ]];then
        network_attachment_definition_file="$WORKSPACE/mellanox-network-operator/config/crd/bases/k8s.cni.cncf.io_networkattachmentdefinitions_crd.yaml"
    else
        network_attachment_definition_file="$WORKSPACE/mellanox-network-operator/deploy/crds/k8s.cni.cncf.io_networkattachmentdefinitions_crd.yaml"
    fi

    kubectl create -f "$network_attachment_definition_file"

    unlabel_master

    configure_common "$sample_file"
    configure_images_specs "secondaryNetwork.multus" "$sample_file"
    configure_images_specs "secondaryNetwork.cniPlugins" "$sample_file"
    configure_images_specs "secondaryNetwork.ipamPlugin" "$sample_file"

    nic_policy_create "$sample_file"
    let status=status+$?
    if [ "$status" != 0 ]; then
        echo "Error: error in creating the example nic_policy."
        return $status
    fi

    sleep 10

    local macvlan_sample_file="$ARTIFACTS"/example-macvlan-cr.yaml

    configure_macvlan_custom_resource "$macvlan_sample_file"
    kubectl create -f "$macvlan_sample_file"

    local test_pod_1_name="secondary-network-test-pod-1"
    local test_pod_2_name="secondary-network-test-pod-2"

    create_test_pod "$test_pod_1_name" "$ARTIFACTS"/"$test_pod_1_name".yaml "" "$MACVLAN_NETWORK_DEFAULT_NAME"
    let status=status+$?
    if [ "$status" != 0 ]; then
        echo "Error: error in creating $test_pod_1_name!"
        return $status
    fi

    create_test_pod "$test_pod_2_name" "$ARTIFACTS"/"$test_pod_2_name".yaml "" "$MACVLAN_NETWORK_DEFAULT_NAME"
    let status=status+$?
    if [ "$status" != 0 ]; then
        echo "Error: error in creating $test_pod_2_name!"
        return $status
    fi

    test_pods_connectivity "$test_pod_1_name" "$test_pod_2_name"
    let status=status+$?
    if [ "$status" != 0 ]; then
        echo "Error: Pods failed the connectivity test!!!"
        return $status
    fi

    echo ""
    echo "Secondary network test Succeeded!!!"
    echo ""

    kubectl delete pods --all

    delete_nic_cluster_policies
    let status=status+$?
    if [ "$status" != 0 ]; then
        echo "Error: Couldn't delete $sample_file!"
        return $status
    fi

    # Note(abdallahyas): Redeploy the multus in the system to bring
    # back the secondary network capabilities to the system.

    multus_configuration

    cp "$macvlan_bin" "$CNI_BIN_DIR"/

    create_macvlan_net

    return 0

}

function test_probes {
    status=0
    local sample_file="$ARTIFACTS"/ofed-nic-cluster-policy.yaml

    configure_common "$sample_file"
    configure_ofed "$sample_file"

    nic_policy_create "$sample_file"
    let status=status+$?
    if [ "$status" != 0 ]; then
        echo "Error: error in creating the example nic_policy."
        return $status
    fi

    sleep 10

    local modules_list="mlx5_ib mlx5_core"

    echo "Testing Probes..."
    echo "Unloading ofed modules..."
    echo ""
    for module in $modules_list;do
        sudo rmmod $module
    done

    wait_nic_policy_states "" "" "notReady"
    if [[ "$?" != "0" ]];then
        return 1
    fi

    wait_nic_policy_states "" "" "ready"
    if [[ "$?" != "0" ]];then
        return 1
    fi

    sleep 10
    for module in $modules_list;do
        if [[ -z "$(lsmod | grep $module)" ]];then
            echo "ERROR: $module is not loaded again!!!"
            return 1
        fi
    done

    delete_nic_cluster_policies
    let status=status+$?
    if [ "$status" != 0 ]; then
        echo "Error: Couldn't delete ofed-rdma-nic-cluster-policy.yaml!"
        return $status
    fi

    echo "Probes test success!!!"
    echo ""
    return 0
}

function test_predefined_name {
    status=0
    echo "Testing Predefined NicClusterPolicy name feature..."
    echo ""

    local sample_file="$ARTIFACTS"/failing-nic-cluster-policy.yaml

    configure_common "$sample_file" "failing-nic-cluster-policy"
    configure_device_plugin "$sample_file"

    kubectl create -f $sample_file

    wait_nic_policy_states "failing-nic-cluster-policy" "" "ignore"
    let status=status+$?
    if [ "$status" != 0 ]; then
        echo "Error: NicClusterPolicy state did not become ignere!."
        return $status
    fi

    delete_nic_cluster_policies
    let status=status+$?
    if [ "$status" != 0 ]; then
        echo "Error: Couldn't delete $sample_file!"
        return $status
    fi

    echo "Predefined name test success!!!"
    echo ""
    return 0
}


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

    test_ofed_only
    let status=status+$?
    if [ "$status" != 0 ]; then
        echo "Error: Testing deploying the OFED only failed!!"
        exit_code $status
    fi
    
    sleep 10

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

    test_nv_peer_mem
    let status=status+$?
    if [ "$status" != 0 ]; then
        echo "Error: Testing deploying OFED, RDMA, and nv-peer-mem failed!!"
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

