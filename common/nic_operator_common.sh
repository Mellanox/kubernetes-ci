#/bin/bash

export WORKSPACE=${WORKSPACE:-/tmp/k8s_$$}
export LOGDIR=$WORKSPACE/logs
export ARTIFACTS=$WORKSPACE/artifacts
export TIMEOUT=${TIMEOUT:-600}
export POLL_INTERVAL=${POLL_INTERVAL:-10}

export KUBECONFIG=${KUBECONFIG:-/etc/kubernetes/admin.conf}

export SRIOV_INTERFACE=${SRIOV_INTERFACE:-auto_detect}

export MACVLAN_NETWORK_DEFAULT_NAME=${MACVLAN_NETWORK_DEFAULT_NAME:-'example-macvlan'}
export HOSTDEVICE_NETWORK_DEFAULT_NAME=${HOSTDEVICE_NETWORK_DEFAULT_NAME:-'example-hostdevice-network'}

export nic_operator_dir=$WORKSPACE/mellanox-network-operator/
export NIC_OPERATOR_NAMESPACE_FILE=${NIC_OPERATOR_NAMESPACE_FILE:-"$nic_operator_dir/deploy/operator-ns.yaml"}
export NIC_OPERATOR_RESOURCES_NAMESPACE_FILE=${NIC_OPERATOR_RESOURCES_NAMESPACE_FILE:-"$nic_operator_dir/deploy/operator-resources-ns.yaml"}
export IMAGES_SRC_FILE="$nic_operator_dir/deployment/network-operator/values.yaml"

export NIC_OPERATOR_REPO=${NIC_OPERATOR_REPO:-https://github.com/Mellanox/network-operator}
export NIC_OPERATOR_BRANCH=${NIC_OPERATOR_BRANCH:-''}
export NIC_OPERATOR_PR=${NIC_OPERATOR_PR:-''}
export NIC_OPERATOR_HARBOR_IMAGE=${NIC_OPERATOR_HARBOR_IMAGE:-${HARBOR_REGESTRY}/${HARBOR_PROJECT}/network-operator}

export OFED_DRIVER_IMAGE='modified-mofed'
export OFED_DRIVER_REPO='docker.io/mellanox'
export OFED_DRIVER_VERSION='1.0.0'

export DEVICE_PLUGIN_IMAGE=${DEVICE_PLUGIN_IMAGE:-''}
export DEVICE_PLUGIN_REPO=${DEVICE_PLUGIN_REPO:-''}
export DEVICE_PLUGIN_VERSION=${DEVICE_PLUGIN_VERSION:-''}

export RDMA_SHARED_DEVICE_PLUGIN_IMAGE=${RDMA_SHARED_DEVICE_PLUGIN_IMAGE:-''}
export RDMA_SHARED_DEVICE_PLUGIN_REPO=${RDMA_SHARED_DEVICE_PLUGIN_REPO:-''}
export RDMA_SHARED_DEVICE_PLUGIN_VERSION=${RDMA_SHARED_DEVICE_PLUGIN_VERSION:-''}

export NV_PEER_DRIVER_IMAGE=${NV_PEER_DRIVER_IMAGE:-''}
export NV_PEER_DRIVER_REPO=${NV_PEER_DRIVER_REPO:-''}
export NV_PEER_DRIVER_VERSION=${NV_PEER_DRIVER_VERSION:-''}

export SECONDARY_NETWORK_MULTUS_IMAGE=${SECONDARY_NETWORK_MULTUS_IMAGE:-''}
export SECONDARY_NETWORK_MULTUS_REPO=${SECONDARY_NETWORK_MULTUS_REPO:-''}
export SECONDARY_NETWORK_MULTUS_VERSION=${SECONDARY_NETWORK_MULTUS_VERSION:-''}

export SECONDARY_NETWORK_CNI_PLUGINS_IMAGE=${SECONDARY_NETWORK_CNI_PLUGINS_IMAGE:-''}
export SECONDARY_NETWORK_CNI_PLUGINS_REPO=${SECONDARY_NETWORK_CNI_PLUGINS_REPO:-''}
export SECONDARY_NETWORK_CNI_PLUGINS_VERSION=${SECONDARY_NETWORK_CNI_PLUGINS_VERSION:-''}

export SECONDARY_NETWORK_IPAM_PLUGIN_IMAGE=${SECONDARY_NETWORK_IPAM_PLUGIN_IMAGE:-''}
export SECONDARY_NETWORK_IPAM_PLUGIN_REPO=${SECONDARY_NETWORK_IPAM_PLUGIN_REPO:-''}
export SECONDARY_NETWORK_IPAM_PLUGIN_VERSION=${SECONDARY_NETWORK_IPAM_PLUGIN_VERSION:-''}

export SRIOV_DEVICE_PLUGIN_IMAGE=${SRIOV_DEVICE_PLUGIN_IMAGE:-''}
export SRIOV_DEVICE_PLUGIN_REPO=${SRIOV_DEVICE_PLUGIN_REPO:-''}
export SRIOV_DEVICE_PLUGIN_VERSION=${SRIOV_DEVICE_PLUGIN_VERSION:-''}

export NIC_OPERATOR_HELM_NAME=${NIC_OPERATOR_HELM_NAME:-'network-operator-helm-ci'}
export NIC_OPERATOR_CRD_NAME=${NIC_OPERATOR_CRD_NAME:-'nicclusterpolicies.mellanox.com'}

export GPU_OPERATOR_VERSION=${GPU_OPERATOR_VERSION:-'1.5.2'}
export GPU_OPERATOR_CRD_NAME=${GPU_OPERATOR_CRD_NAME:-'clusterpolicies.nvidia.com'}
export GPU_OPERATOR_POLICY_NAME=${GPU_OPERATOR_POLICY_NAME:-'cluster-policy'}

export MODIFIED_MOFED_CONTAINER_NAME="${OFED_DRIVER_REPO}/${OFED_DRIVER_IMAGE}-${OFED_DRIVER_VERSION}:ubuntu20.04-amd64"

function configure_macvlan_custom_resource {
    local file_name="$1"

    if [[ $SRIOV_INTERFACE == 'auto_detect' ]]; then
        SRIOV_INTERFACE=$(get_auto_net_device)
    fi

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

function configure_hostdevice_network_custom_resource {
    local hostdevice_resource_name="$1"
    local file_name="$2"

    if [[ ! -f "$file_name" ]];then
        touch "$file_name"
    fi

    yaml_write "apiVersion" "mellanox.com/v1alpha1" "$file_name"
    yaml_write "kind" "HostDeviceNetwork" "$file_name"
    yaml_write "metadata.name" "$HOSTDEVICE_NETWORK_DEFAULT_NAME" "$file_name"

    yaml_write "spec.networkNamespace" "default" "$file_name"
    yaml_write "spec.resourceName" "$hostdevice_resource_name" "$file_name"

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

function unlabel_master {
    kubectl label node $(kubectl get nodes -o name | cut -d'/' -f 2) node-role.kubernetes.io/master-
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

    ofed_module=$(kubectl exec -n "$(get_nic_operator_resources_namespace)" $ofed_pod_name -- modinfo $module | grep srcversion | cut -d':' -f 2 | tr -d ' ')
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

function get_nic_policy_state {
    local resource_name=$1
    local state_name=$2

    local lower_state_name="$(tr [:upper:] [:lower:] <<< $state_name)"

    local nic_policy_status=$(kubectl get "$NIC_OPERATOR_CRD_NAME" \
        -n "$(get_nic_operator_namespace)" "$resource_name" -o yaml)

    if [[ "$state_name" == "state" ]];then
        yq r - status.state <<< ${nic_policy_status}
        return 0
    fi

    local number_of_applied_status=$(yq r - status.appliedStates -l <<< ${nic_policy_status})

    for index in $(seq 0 "$number_of_applied_status"); do
        if [[ "$(yq r - status.appliedStates[$index].name <<< ${nic_policy_status} | \
              tr [:upper:] [:lower:])"  == "$lower_state_name" ]];then
            yq r - status.appliedStates[$index].state <<< ${nic_policy_status}
            return 0
        fi
    done
    return 1
}

function wait_nic_policy_states {
    local cr_name=${1:-nic-cluster-policy}
    local state_key=${2:-state}
    local wanted_state=${3:-ready}

    cr_status="$(get_nic_policy_state $cr_name $state_key)"
    let stop=$(date '+%s')+$TIMEOUT
    d=$(date '+%s')
    while [ $d -lt $stop ]; do
        echo "Waiting for $cr_name to become $wanted_state"
        cr_status="$(get_nic_policy_state $cr_name $state_key)"
        if [[ "$cr_status" == "$wanted_state" ]]; then
            echo "$cr_name is $wanted_state!"
            return 0
        elif [ "$cr_status" == "UnexpectedAdmissionError" ]; then
            kubectl delete -f $cr_file
            sleep ${POLL_INTERVAL}
            kubectl create -f $cr_file
        fi
        kubectl get "$NIC_OPERATOR_CRD_NAME" -n "$(get_nic_operator_namespace)" "$cr_name"
        sleep ${POLL_INTERVAL}
        d=$(date '+%s')

    done
    kubectl describe "$NIC_OPERATOR_CRD_NAME" -n "$(get_nic_operator_namespace)" "$cr_name"
    echo "Error $cr_name is not up"
    return 1
}

function build_nic_operator_image {
    build_github_project "nic-operator" "TAG=$NIC_OPERATOR_HARBOR_IMAGE make image"

    let status=status+$?

    if [ "$status" != 0 ]; then
        echo "ERROR: Failed to build the nic-operator project!"
        return $status
    fi

    change_image_name $NIC_OPERATOR_HARBOR_IMAGE mellanox/network-operator
    mv $WORKSPACE/nic-operator $nic_operator_dir
}

function get_nic_operator_namespace {
    if [[ ! -f "$NIC_OPERATOR_NAMESPACE_FILE" ]];then
        echo "nvidia-network-operator"
        return 0
    fi

    yaml_read metadata.name "$NIC_OPERATOR_NAMESPACE_FILE"
}

function get_nic_operator_resources_namespace {
    if [[ ! -f "$NIC_OPERATOR_RESOURCES_NAMESPACE_FILE" ]];then
        echo "nvidia-network-operator-resources"
        return 0
    fi

    yaml_read metadata.name "$NIC_OPERATOR_RESOURCES_NAMESPACE_FILE"
}

function deploy_gpu_operator {
    local values_file_name="$ARTIFACTS/gpu-operator-values.yaml"

    render_gpu_operator_value "$values_file_name"

    helm repo add nvidia https://nvidia.github.io/gpu-operator
    helm repo update
    
    helm install --version "$GPU_OPERATOR_VERSION" -f "$values_file_name" gpu-operator\
      nvidia/gpu-operator --wait --devel

    wait_pod_state "nvidia-device-plugin-validation" "Completed"
    return $?
}

function get_cluster_policy_state {
    local resource_name=$1

    local cluster_policy_status=$(kubectl get "$GPU_OPERATOR_CRD_NAME" \
        "$resource_name" -o yaml)

    yq r - status.state <<< ${cluster_policy_status}
    return $?
}

function render_gpu_operator_value {
    local file="${1:-$ARTIFACTS/gpu-operator-values.yaml}"

    if [[ ! -f "$file" ]];then
        touch "$file"
    fi

    yaml_write "node-feature-discovery.config" "\
sources:
  pci:
    deviceLabelFields:
    - vendor
    deviceClassWhitelist:
    - \"03\"
    - \"02\"
    - \"0200\"
    - \"0207\"
" "$file"
}

function pull_general_component_image {
    local component_key="$1"
    local file="$2"
    local kind_netns="$3"

    local image_repo=$(yaml_read "${component_key}.repository" "$file")
    local image_name=$(yaml_read "${component_key}.image" "$file")
    local image_tag=$(yaml_read "${component_key}.version" "$file")

    local image="${image_repo}/${image_name}:${image_tag}"

    sudo docker pull $image

    if [[ -n "$kind_netns" ]];then
        upload_image_to_kind "$image" "$kind_netns"
    fi
}

function pull_and_build_ofed_container_image {
    local mofed_key="$1"
    local file="$2"
    local kind_netns="$3"

    local image_repo=$(yaml_read "${mofed_key}.repository" "$file")
    local image_name=$(yaml_read "${mofed_key}.image" "$file")
    local image_version=$(yaml_read "${mofed_key}.version" "$file")

    local image="${image_repo}/${image_name}-${image_version}:$(get_distro)$(get_distro_version)-amd64"

    sudo docker pull $image

    prebuild_mofed_contianer $image

    if [[ -n "$kind_netns" ]];then
        upload_image_to_kind "$MODIFIED_MOFED_CONTAINER_NAME" "$kind_netns"
    fi
}

function pull_nvpeer_container_image {
    local nvpeer_key="$1"
    local file="$2"

    local image_repo=$(yaml_read "${nvpeer_key}.repository" "$file")
    local image_name=$(yaml_read "${nvpeer_key}.image" "$file")
    local image_version=$(yaml_read "${nvpeer_key}.version" "$file")

    local image="${image_repo}/${image_name}-${image_version}:amd64-$(get_distro)$(get_distro_version)"

    sudo docker pull $image
}

function pull_network_operator_images {
    local kind_netns="$1"

    pull_and_build_ofed_container_image "ofedDriver" "$IMAGES_SRC_FILE" "$kind_netns"

    pull_general_component_image "rdmaSharedDevicePlugin" "$IMAGES_SRC_FILE" "$kind_netns"

    pull_nvpeer_container_image "nvPeerDriver" "$IMAGES_SRC_FILE"

    pull_general_component_image "secondaryNetwork.cniPlugins" "$IMAGES_SRC_FILE" "$kind_netns"

    pull_general_component_image "secondaryNetwork.multus" "$IMAGES_SRC_FILE" "$kind_netns"

    pull_general_component_image "secondaryNetwork.ipamPlugin" "$IMAGES_SRC_FILE" "$kind_netns"

    pull_general_component_image "sriovDevicePlugin" "$IMAGES_SRC_FILE" "$kind_netns"
}

function configure_images_variable {
    local key="$1"

    local image="$(yaml_read "${key}.image" "$IMAGES_SRC_FILE")"
    local repo="$(yaml_read "${key}.repository" "$IMAGES_SRC_FILE")"
    local version="$(yaml_read "${key}.version" "$IMAGES_SRC_FILE")"

    local upper_case_key="$(sed 's/[A-Z]/\.\0/g' <<< $key | tr "." "_" | tr '[:lower:]' '[:upper:]')"

    local image_variable="${upper_case_key}_IMAGE"
    local repo_variable="${upper_case_key}_REPO"
    local version_variable="${upper_case_key}_VERSION"

    export ${image_variable}="$image"
    export ${repo_variable}="$repo"
    export ${version_variable}="$version"
}

function set_network_operator_images_variables {
    configure_images_variable "rdmaSharedDevicePlugin"

    configure_images_variable "sriovDevicePlugin"

    configure_images_variable "nvPeerDriver"

    configure_images_variable "secondaryNetwork.cniPlugins"

    configure_images_variable "secondaryNetwork.multus"

    configure_images_variable "secondaryNetwork.ipamPlugin"
}

function configure_common {
    local file_name="$1"
    local nic_policy_name=${2:-"$NIC_CLUSTER_POLICY_DEFAULT_NAME"}

    if [[ -f "$file_name" ]];then
        rm -rf "$file_name"
    fi

    touch "$file_name"

    yaml_write 'apiVersion' 'mellanox.com/v1alpha1' "$file_name"
    yaml_write 'kind' 'NicClusterPolicy' "$file_name"
    yaml_write 'metadata.name' "$nic_policy_name" "$file_name"
    yaml_write 'metadata.namespace' "$(get_nic_operator_namespace)" "$file_name"

    configure_images_specs "secondaryNetwork.multus" "$file_name"
    configure_images_specs "secondaryNetwork.cniPlugins" "$file_name"
    configure_images_specs "secondaryNetwork.ipamPlugin" "$file_name"
}

function configure_ofed {
    local file_name="$1"

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

function configure_host_device {
    local file_name="$1"
    local resource_prefix=${2:-'nvidia.com'}
    local resource_name=${3:-'hostdev'}

    if [[ -n "$project" ]];then
        local netns="${project}-worker"
    else
        local netns=""
    fi

    local pf_device_id=$(get_pf_device_id "$netns")

    configure_images_specs "sriovDevicePlugin" "$file_name"

    yaml_write spec.sriovDevicePlugin.config "\
{
  \"resourceList\": [
    {
      \"resourcePrefix\": \"$resource_prefix\",
      \"resourceName\": \"$resource_name\",
      \"selectors\": {
        \"isRdma\": true,
        \"drivers\": [\"mlx5_core\"],
        \"devices\": [\"$pf_device_id\"]
      }
    }
  ]
}
" "$file_name"
}

function configure_nv_peer_mem {
    local file_name="$1"

    configure_images_specs "nvPeerDriver" "$file_name"
    yaml_write spec.nvPeerDriver.gpuDriverSourcePath "/run/nvidia/driver"\
     "$file_name"
}

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

function prebuild_mofed_contianer {
    local src_image="$1"

    sudo docker build -f "${SCRIPTS_DIR}/Dockerfile.ofed_rebuild" --build-arg image="$src_image"\
        -t "$MODIFIED_MOFED_CONTAINER_NAME" "$SCRIPTS_DIR"
}
