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

export OFED_DRIVER_IMAGE=${OFED_DRIVER_IMAGE:-'mofed'}
export OFED_DRIVER_REPO=${OFED_DRIVER_REPO:-'harbor.mellanox.com/sw-linux-devops'}
export OFED_DRIVER_VERSION=${OFED_DRIVER_VERSION:-'5.2-0.3.1.0'}

export DEVICE_PLUGIN_IMAGE=${DEVICE_PLUGIN_IMAGE:-'k8s-rdma-shared-dev-plugin'}
export DEVICE_PLUGIN_REPO=${DEVICE_PLUGIN_REPO:-'mellanox'}
export DEVICE_PLUGIN_VERSION=${DEVICE_PLUGIN_VERSION:-'latest'}

export SECONDARY_NETWORK_MULTUS_IMAGE=${SECONDARY_NETWORK_MULTUS_IMAGE:-'multus'}
export SECONDARY_NETWORK_MULTUS_REPO=${SECONDARY_NETWORK_MULTUS_REPO:-'nfvpe'}
export SECONDARY_NETWORK_MULTUS_VERSION=${SECONDARY_NETWORK_MULTUS_VERSION:-'v3.6'}

export SECONDARY_NETWORK_CNI_PLUGINS_IMAGE=${SECONDARY_NETWORK_CNI_PLUGINS_IMAGE:-'containernetworking-plugins'}
export SECONDARY_NETWORK_CNI_PLUGINS_REPO=${SECONDARY_NETWORK_CNI_PLUGINS_REPO:-'mellanox'}
export SECONDARY_NETWORK_CNI_PLUGINS_VERSION=${SECONDARY_NETWORK_CNI_PLUGINS_VERSION:-'v0.8.7'}

export SECONDARY_NETWORK_IPAM_PLUGIN_IMAGE=${SECONDARY_NETWORK_IPAM_PLUGIN_IMAGE:-'whereabouts'}
export SECONDARY_NETWORK_IPAM_PLUGIN_REPO=${SECONDARY_NETWORK_IPAM_PLUGIN_REPO:-'dougbtv'}
export SECONDARY_NETWORK_IPAM_PLUGIN_VERSION=${SECONDARY_NETWORK_IPAM_PLUGIN_VERSION:-'latest'}

export NIC_CLUSTER_POLICY_DEFAULT_NAME='nic-cluster-policy'
export MACVLAN_NETWORK_DEFAULT_NAME='example-macvlan'

export CNI_BIN_DIR=${CNI_BIN_DIR:-'/opt/cni/bin'}

nic_operator_dir=$WORKSPACE/mellanox-network-operator/deploy

source ./common/common_functions.sh
source ./common/clean_common.sh

test_pod_image='harbor.mellanox.com/cloud-orchestration/rping-test'

function nic_policy_create {
    status=0
    cr_file="$1"

    kubectl create -f "$cr_file"

    wait_nic_policy_state "$cr_file" "ready"
    let status=status+$?
    if [ "$status" != 0 ]; then
        echo "Error: error in creating $cr_file!"
        return $status
    fi
    return 0
}

function get_nic_policy_state {
    local resource_definition_name=$1
    local policy_namespace=$2
    local resource_name=$3

    kubectl get "$resource_definition_name" -n "$policy_namespace" "$resource_name" -o yaml | yq r - status.state
}

function test_ofed_drivers {
    local status=0

    ofed_pod_name=$(kubectl get pods -A -o name | grep ofed | cut -d/ -f2)
    if [[ -z "$ofed_pod_name" ]]; then
        echo "Could not find a working ofed pod !!!"
        return 1
    fi

    echo "
Testing ofed drivers ..."
    verfiy_module mlx5_core
    let status=status+$?
    verfiy_module ib_core
    let status=status+$?
    verfiy_module mlx_compat
    let status=status+$?
    verfiy_module mlx5_ib
    let status=status+$?

    if [[ "$status" == "0" ]]; then
        echo "Success!! all ofed modules are verified."
    else
        echo "There are issues with the ofed modules!!"
    fi

    return $status
}

function verfiy_module {
    local module=$1
    echo "$module: verifying ..."
    loaded_module=$(cat /sys/module/$module/srcversion)
    if [[ -z "$loaded_module" ]];then
        echo "Error: couldn't get the loaded module signture!!"
	return 1
    fi

    operator_resourses_namespace=$(yaml_read metadata.name $nic_operator_dir/operator-resources-ns.yaml)

    ofed_module=$(kubectl exec -n $operator_resourses_namespace $ofed_pod_name -- modinfo $module | grep srcversion | cut -d':' -f 2 | tr -d ' ')
    if [[ -z "$ofed_module" ]];then
         echo "Error: couldn't get the ofed module signture!!"
         return 1
    fi

    if [[ "$loaded_module" == "$ofed_module" ]]; then
        echo "$module: OK!	
"
	return 0
    else
	echo "$module: Failed!
"
	return 1
    fi
}

function create_rdma_test_pod {
    local pod_name=$1
    local rdma_resource_name=rdma/$2

    local test_pod_file=${ARTIFACTS}/${pod_name}.yaml

    cp "$ARTIFACTS"/sample-test-pod.yaml $test_pod_file

    yaml_write metadata.name $pod_name $test_pod_file
    yaml_write spec.containers[0].image $test_pod_image $test_pod_file
    yaml_write spec.containers[0].resources.requests.$rdma_resource_name 1 $test_pod_file
    yaml_write spec.containers[0].resources.limits.$rdma_resource_name 1 $test_pod_file

    kubectl create -f "$ARTIFACTS"/"$pod_name".yaml
    wait_pod_state $pod_name 'Running'
    if [[ "$?" != 0 ]];then
        echo "Error Running $pod_name!!"
        return 1
    fi

    echo "$pod_name is now running."
    sleep 5
    return 0
}

function test_rdma_rping {
    pod_name1=$1
    pod_name2=$2
    echo "Testing Rping between $pod_name1 and $pod_name2"
    
    ip_1=$(/usr/local/bin/kubectl exec -i $pod_name1 -- ifconfig net1 | grep inet | awk '{print $2}')
    /usr/local/bin/kubectl exec -i $pod_name1 -- ifconfig net1
    echo "$pod_name1 has ip ${ip_1}"

    screen -S rping_server -d -m bash -x -c "kubectl exec -t $pod_name1 -- rping -svd"
    sleep 20
    kubectl exec -t $pod_name2 -- rping -cvd -a $ip_1 -C 1

    return $?
}

function test_rdma_plugin {
    status=0
    local test_pod_1_name='test-pod-1'
    local test_pod_2_name='test-pod-2'

    echo "Testing RDMA shared mode device plugin."
    echo ""
    echo "Creating testing pods."

    create_rdma_test_pod $test_pod_1_name hca_shared_devices_a
    let status=status+$?
    if [ "$status" != 0 ]; then
        echo "Error: error in creating $test_pod_1_name!"
        return $status
    fi

    create_rdma_test_pod $test_pod_2_name hca_shared_devices_a
    let status=status+$?
    if [ "$status" != 0 ]; then
        echo "Error: error in creating $test_pod_2_name!"
        return $status
    fi
    
    echo "checking if the rdma resources were mounted."

    kubectl exec -it $test_pod_1_name -- ls -l /dev/infiniband
    if [[ "$?" != "0" ]]; then
        echo "pod $test_pod_1_name /dev/infiniband directory is empty! failing the test."
	return 1
    fi

    kubectl exec -it $test_pod_2_name -- ls -l /dev/infiniband
    if [[ "$?" != "0" ]]; then
        echo "pod $test_pod_2_name /dev/infiniband directory is empty! failing the test."
        return 1
    fi

    echo ""
    echo "rdma resources are available inside the testing pods!"
    echo ""

    test_rdma_rping $test_pod_1_name $test_pod_2_name
    let status=status+$?
    if [ "$status" != 0 ]; then
        echo "Error: error testing the rping between $test_pod_1_name $test_pod_2_name!"
        return $status
    fi

    echo "Deleting test pods..."
    kubectl delete -f ${ARTIFACTS}/${test_pod_1_name}.yaml
    kubectl delete -f ${ARTIFACTS}/${test_pod_2_name}.yaml
    sleep 5
    
    return $status
}

function test_deleting_network_operator {
    echo ""
    echo "Test Deleting Network Operator...."
    status=0

    local sample_file="$ARTIFACTS"/ofed-nic-cluster-policy.yaml

    configure_common "$sample_file"
    configure_ofed

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

    if [[ ! -f "$file_name" ]];then
        touch "$file_name"
    fi

    yaml_write 'apiVersion' 'mellanox.com/v1alpha1' "$file_name"
    yaml_write 'kind' 'NicClusterPolicy' "$file_name"
    yaml_write 'metadata.name' "$nic_policy_name" "$file_name"
    yaml_write 'metadata.namespace' 'mlnx-network-operator' "$file_name"
}

function configure_ofed {
    local file_name="$1"

    modprobe -r rpcrdma

    configure_images_specs "ofedDriver" "$sample_file"
}

function configure_device_plugin {
    local file_name="$1"
    local rdma_resource_name=${2:-'hca_shared_devices_a'}

    configure_images_specs "devicePlugin" "$file_name"

    yaml_write spec.devicePlugin.config "\
{
  \"configList\": [{
    \"resourceName\": \"$rdma_resource_name\",
    \"rdmaHcaMax\": 1000,
    \"devices\": [\"$SRIOV_INTERFACE\"]
  }]
}
" "$file_name"
}

function configure_macvlan_custom_resource {
    local file_name="$1"

    if [[ ! -f "$file_name" ]];then
        touch "$file_name"
    fi

    yaml_write "apiVersion" "mellanox.com/v1alpha1" "$file_name"
    yaml_write "kind" "MacvlanNetwork" "$file_name"
    yaml_write "metadata.name" "$MACVLAN_NETWORK_DEFAULT_NAME" "$file_name"

    yaml_write "spec.networkNamespace" "default" "$file_name"
    yaml_write "spec.master" "$SRIOV_INTERFACE" "$file_name"
    yaml_write "spec.mode" "bridge" "$file_name"
    yaml_write "spec.mtu" "1500" "$file_name"

    yaml_write "spec.ipam" "\
{
  \"type\": \"whereabouts\",
  \"datastore\": \"kubernetes\",
  \"kubernetes\": {
    \"kubeconfig\": \"/etc/cni/net.d/whereabouts.d/whereabouts.kubeconfig\"
  },
  \"range\": \"192.168.2.225/28\",
  \"exclude\": [
    \"192.168.2.229/30\",
    \"192.168.2.236/32\"
  ],
  \"log_file\" : \"/var/log/whereabouts.log\",
  \"log_level\" : \"info\",
  \"gateway\": \"192.168.2.1\"
}
" "$file_name"

}

function test_ofed_only {
    status=0
    local sample_file="$ARTIFACTS"/ofed-nic-cluster-policy.yaml

    configure_common "$sample_file"
    configure_ofed

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
    configure_ofed
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

function test_secondary_network {
    status=0
    local sample_file="$ARTIFACTS"/seconday-network-nic-cluster-policy.yaml
    local multus_file="$WORKSPACE/multus-cni/images/multus-daemonset.yml"

    echo ""
    echo "Testing Secondary networks..."

    if [[ -f "$multus_file" ]];then
        kubectl delete -f "$multus_file"
    fi

    sudo rm -f "${CNI_BIN_DIR}/macvlan"
    sudo rm -f "${CNI_BIN_DIR}/multus"
    sudo rm -f "${CNI_BIN_DIR}/whereabouts"

    kubectl create -f $WORKSPACE/mellanox-network-operator/deploy/crds/k8s.cni.cncf.io_networkattachmentdefinitions_crd.yaml

    kubectl label node $(kubectl get nodes -o name | cut -d'/' -f 2) node-role.kubernetes.io/master-

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

    local modules_list="mlx5_fpga_tools mlx5_ib mlx5_core"

    echo "Testing Probes..."
    echo "Unloading ofed modules..."
    echo ""
    for module in $modules_list;do
        sudo rmmod $module
    done

    wait_nic_policy_state "$cr_file" "notReady"
    if [[ "$?" != "0" ]];then
        return 1
    fi

    wait_nic_policy_state "$cr_file" "ready"
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


function wait_nic_policy_state {
    local local_cr_file="$1"
    local target_state="$2"

    local cr_name=$(yaml_read metadata.name $local_cr_file)
    if [[ -z "$cr_name" ]]; then
        echo "Could not get the name of the example nicpolicy in $local_cr_file !!!"
        return 1
    fi

    local operator_namespace=$(yaml_read metadata.name $nic_operator_dir/operator-ns.yaml)
    if [[ -z "$operator_namespace" ]]; then
        echo "Could not find operatore name space in $nic_operator_dir/operator-ns.yaml !!!"
        return 1
    fi

    local nicpolicy_crd_name=$(yaml_read metadata.name $nic_operator_dir/crds/mellanox.com_nicclusterpolicies_crd.yaml)
    if [[ -z "$nicpolicy_crd_name" ]]; then
        echo "Could not find the CRD name in $local_nic_operator_dir/crds/mellanox.com_nicclusterpolicies_crd.yaml !!!"
        return 1
    fi

    let stop=$(date '+%s')+$TIMEOUT
    local d=$(date '+%s')
    while [ $d -lt $stop ]; do
        echo "Waiting for $cr_name to become $target_state"
        cr_status=$(get_nic_policy_state $nicpolicy_crd_name $operator_namespace $cr_name)
        if [ "$cr_status" == "$target_state" ]; then
            echo "$cr_name is $target_state!
"
            return 0
        elif [ "$cr_status" == "UnexpectedAdmissionError" ]; then
            kubectl delete -f $cr_file
            sleep ${POLL_INTERVAL}
            kubectl create -f $cr_file
        fi
        kubectl get "$nicpolicy_crd_name" -n "$operator_namespace" "$cr_name"
        kubectl describe "$nicpolicy_crd_name" -n "$operator_namespace" "$cr_name"
        sleep ${POLL_INTERVAL}
        d=$(date '+%s')
    done
    echo "ERROR: $cr_name did not become $target_state after $TIMEOUT have passed!"
    exit 1
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

