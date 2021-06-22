#!/bin/bash

function test_deleting_network_operator {
    echo ""
    echo "Test Deleting Network Operator...."
    status=0

    local sample_file="$ARTIFACTS"/ofed-nic-cluster-policy.yaml

    configure_common "$sample_file"
    configure_ofed "$sample_file"

    nic_policy_create "$sample_file"
    let status=$status+$?
    if [[ "$status" != "0" ]]; then
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

    load_core_drivers
    sleep 2

    load_rdma_modules
    sleep 2

    local sample_file="$ARTIFACTS"/rdma-nic-cluster-policy.yaml

    configure_common "$sample_file"
    configure_device_plugin "$sample_file"

    nic_policy_create "$sample_file"
    let status=$status+$?
    if [[ "$status" != "0" ]]; then
        echo "Error: error in creating the example nic_policy."
        return $status
    fi

    sleep 10

    test_rdma_plugin "" "$MACVLAN_NETWORK_DEFAULT_NAME" "rdma/rdma_shared_devices_a"
    let status=$status+$?
    if [[ "$status" != "0" ]]; then
        echo "Error: RDMA device plugin testing Failed!"
        return $status
    fi

    delete_nic_cluster_policies
    let status=$status+$?
    if [[ "$status" != "0" ]]; then
        echo "Error: Couldn't delete $sample_file!"
        return $status
    fi
    return 0
}

function test_ofed_only {
    status=0
    local sample_file="$ARTIFACTS"/ofed-nic-cluster-policy.yaml

    configure_common "$sample_file"
    configure_ofed "$sample_file"

    nic_policy_create "$sample_file"
    let status=$status+$?
    if [[ "$status" != "0" ]]; then
        echo "Error: error in creating the example nic_policy."
        return $status
    fi

    sleep 10

    test_ofed_drivers
    let status=$status+$?
    if [[ "$status" != "0" ]]; then
        echo "Error: Ofed modules failed!"
        return $status
    fi

    delete_nic_cluster_policies
    let status=$status+$?
    if [[ "$status" != "0" ]]; then
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
    let status=$status+$?
    if [[ "$status" != "0" ]]; then
        echo "Error: error in creating the example nic_policy."
        return $status
    fi

    sleep 10

    test_ofed_drivers
    let status=$status+$?
    if [[ "$status" != "0" ]]; then
        echo "Error: Ofed modules failed!"
        return $status
    fi

    test_rdma_plugin "" "$MACVLAN_NETWORK_DEFAULT_NAME" "rdma/rdma_shared_devices_a"
    let status=$status+$?
    if [[ "$status" != "0" ]]; then
        echo "Error: RDMA device plugin testing Failed!"
        return $status
    fi

    delete_nic_cluster_policies
    let status=$status+$?
    if [[ "$status" != "0" ]]; then
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
    let status=$status+$?
    if [[ "$status" != "0" ]]; then
        echo "Error: error in creating the example nic_policy."
        return $status
    fi

    sleep 10

    test_ofed_drivers
    let status=$status+$?
    if [[ "$status" != "0" ]]; then
        echo "Error: Ofed modules failed!"
        return $status
    fi

    test_gpu_direct "harbor.mellanox.com/cloud-orchestration/cuda-perftest:Ubuntu20.04-cuda-devel-11.2.1"\
        "$MACVLAN_NETWORK_DEFAULT_NAME"
    let status=$status+$?
    if [[ "$status" != "0" ]]; then
        echo "Error: nv-peer-mem driver testing Failed!"
        return $status
    fi
    delete_nic_cluster_policies
    let status=$status+$?
    if [[ "$status" != "0" ]]; then
        echo "Error: Couldn't delete $sample_file!"
        return $status
    fi

    undeploy_gpu_operator
    let status=$status+$?
    if [[ "$status" != "0" ]]; then
        echo "Error: Couldn't undeploy the GPU operator!"
        return $status
    fi
}

function test_secondary_network {
    status=0
    local sample_file="$ARTIFACTS"/seconday-network-nic-cluster-policy.yaml

    echo ""
    echo "Testing Secondary networks..."

    configure_common "$sample_file"

    nic_policy_create "$sample_file"
    let status=$status+$?
    if [[ "$status" != "0" ]]; then
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
    let status=$status+$?
    if [[ "$status" != "0" ]]; then
        echo "Error: error in creating $test_pod_1_name!"
        return $status
    fi

    create_test_pod "$test_pod_2_name" "$ARTIFACTS"/"$test_pod_2_name".yaml "" "$MACVLAN_NETWORK_DEFAULT_NAME"
    let status=$status+$?
    if [[ "$status" != "0" ]]; then
        echo "Error: error in creating $test_pod_2_name!"
        return $status
    fi

    test_pods_connectivity "$test_pod_1_name" "$test_pod_2_name"
    let status=$status+$?
    if [[ "$status" != "0" ]]; then
        echo "Error: Pods failed the connectivity test!!!"
        return $status
    fi

    echo ""
    echo "Secondary network test Succeeded!!!"
    echo ""

    kubectl delete pods --all

    delete_nic_cluster_policies
    let status=$status+$?
    if [[ "$status" != "0" ]]; then
        echo "Error: Couldn't delete $sample_file!"
        return $status
    fi

    return 0

}

function test_probes {
    status=0
    local sample_file="$ARTIFACTS"/ofed-nic-cluster-policy.yaml

    configure_common "$sample_file"
    configure_ofed "$sample_file"

    nic_policy_create "$sample_file"
    let status=$status+$?
    if [[ "$status" != "0" ]]; then
        echo "Error: error in creating the example nic_policy."
        return $status
    fi

    sleep 10

    local modules_list="mlx5_ib mlx5_core"

    echo "Testing Probes..."
    echo "Unloading ofed modules..."
    echo ""
    for module in $modules_list;do
        sudo modprobe -r $module
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
    let status=$status+$?
    if [[ "$status" != "0" ]]; then
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
    let status=$status+$?
    if [[ "$status" != "0" ]]; then
        echo "Error: NicClusterPolicy state did not become ignere!."
        return $status
    fi

    delete_nic_cluster_policies
    let status=$status+$?
    if [[ "$status" != "0" ]]; then
        echo "Error: Couldn't delete $sample_file!"
        return $status
    fi

    echo "Predefined name test success!!!"
    echo ""
    return 0
}

function test_host_device {
    local resource_name_prefix="nvidia.com"
    local resource_name="hostdev"

    status=0

    echo "Testing Host device..."
    echo ""

    load_core_drivers
    sleep 2

    load_rdma_modules
    sleep 2

    local network_file="${ARTIFACTS}/example-hostdevice-network.yaml"

    configure_hostdevice_network_custom_resource "$resource_name" "$network_file"
    kubectl create -f "$network_file"

    local sample_file="$ARTIFACTS"/host-device-nic-cluster-policy.yaml

    configure_common "$sample_file"
    configure_host_device "$sample_file" "$resource_name_prefix" "$resource_name"

    nic_policy_create "$sample_file"
    let status=$status+$?
    if [[ "$status" != "0" ]]; then
        echo "Error: error in creating the example nic_policy."
        return $status
    fi

    sleep 10

    test_rdma_plugin "" "$HOSTDEVICE_NETWORK_DEFAULT_NAME" "${resource_name_prefix}/${resource_name}"
    let status=$status+$?
    if [[ "$status" != "0" ]]; then
        echo "Error: host device plugin testing Failed!"
        return $status
    fi

    delete_nic_cluster_policies
    let status=$status+$?
    if [[ "$status" != "0" ]]; then
        echo "Error: Couldn't delete $sample_file!"
        return $status
    fi
    return 0
}

function test_ofed_and_host_device {
    local resource_name_prefix="nvidia.com"
    local resource_name="hostdev"

    status=0

    echo "Testing OFED and Host device..."
    echo ""

    local network_file="${ARTIFACTS}/example-hostdevice-network.yaml"

    configure_hostdevice_network_custom_resource "$resource_name" "$network_file"
    kubectl create -f "$network_file"

    local sample_file="$ARTIFACTS"/ofed-and-host-device-nic-cluster-policy.yaml

    configure_common "$sample_file"
    configure_ofed "$sample_file"
    configure_host_device "$sample_file" "$resource_name_prefix" "$resource_name"

    nic_policy_create "$sample_file"
    let status=$status+$?
    if [[ "$status" != 0 ]]; then
        echo "Error: error in creating the example nic_policy."
        return $status
    fi

    sleep 10

    test_ofed_drivers
    let status=$status+$?
    if [[ "$status" != "0" ]]; then
        echo "Error: Ofed modules failed!"
        return $status
    fi

    test_rdma_plugin "" "$HOSTDEVICE_NETWORK_DEFAULT_NAME" "${resource_name_prefix}/${resource_name}"
    let status=$status+$?
    if [[ "$status" != "0" ]]; then
        echo "Error: host device plugin testing Failed!"
        return $status
    fi

    delete_nic_cluster_policies
    let status=$status+$?
    if [[ "$status" != "0" ]]; then
        echo "Error: Couldn't delete $sample_file!"
        return $status
    fi
    return 0
}

function test_nv_peer_mem_with_host_device {
    local resource_name_prefix="nvidia.com"
    local resource_name="hostdev"

    status=0

    deploy_gpu_operator
    let status=$status+$?
    if [ "$status" != 0 ]; then
        echo "Error: error in deploying the GPU operator."
        return $status
    fi

    local network_file="${ARTIFACTS}/example-hostdevice-network.yaml"

    configure_hostdevice_network_custom_resource "$resource_name" "$network_file"
    kubectl create -f "$network_file"

    local sample_file="$ARTIFACTS"/ofed-host-device-nv-peer-nic-cluster-policy.yaml

    configure_common "$sample_file"
    configure_ofed "$sample_file"
    configure_host_device "$sample_file" "$resource_name_prefix" "$resource_name"
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

    test_gpu_direct "harbor.mellanox.com/cloud-orchestration/cuda-perftest:Ubuntu20.04-cuda-devel-11.2.1"\
        "$HOSTDEVICE_NETWORK_DEFAULT_NAME" "${resource_name_prefix}/${resource_name}"
    let status=status+$?
    if [ "$status" != 0 ]; then
        echo "Error: nv-peer-mem driver with host device testing Failed!"
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

