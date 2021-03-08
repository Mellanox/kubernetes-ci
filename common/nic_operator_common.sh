#/bin/bash

export WORKSPACE=${WORKSPACE:-/tmp/k8s_$$}
export LOGDIR=$WORKSPACE/logs
export ARTIFACTS=$WORKSPACE/artifacts
export TIMEOUT=${TIMEOUT:-600}
export POLL_INTERVAL=${POLL_INTERVAL:-10}

export KUBECONFIG=${KUBECONFIG:-/etc/kubernetes/admin.conf}

export SRIOV_INTERFACE=${SRIOV_INTERFACE:-auto_detect}

export MACVLAN_NETWORK_DEFAULT_NAME=${MACVLAN_NETWORK_DEFAULT_NAME:-'example-macvlan'}

export nic_operator_dir=$WORKSPACE/mellanox-network-operator/
export NIC_OPERATOR_NAMESPACE_FILE=${NIC_OPERATOR_NAMESPACE_FILE:-"$nic_operator_dir/deploy/operator-ns.yaml"}
export NIC_OPERATOR_RESOURCES_NAMESPACE_FILE=${NIC_OPERATOR_RESOURCES_NAMESPACE_FILE:-"$nic_operator_dir/deploy/operator-resources-ns.yaml"}

export NIC_OPERATOR_REPO=${NIC_OPERATOR_REPO:-https://github.com/Mellanox/network-operator}
export NIC_OPERATOR_BRANCH=${NIC_OPERATOR_BRANCH:-''}
export NIC_OPERATOR_PR=${NIC_OPERATOR_PR:-''}
export NIC_OPERATOR_HARBOR_IMAGE=${NIC_OPERATOR_HARBOR_IMAGE:-${HARBOR_REGESTRY}/${HARBOR_PROJECT}/network-operator}

export OFED_DRIVER_IMAGE=${OFED_DRIVER_IMAGE:-'mofed'}
export OFED_DRIVER_REPO=${OFED_DRIVER_REPO:-'harbor.mellanox.com/sw-linux-devops'}
export OFED_DRIVER_VERSION=${OFED_DRIVER_VERSION:-'5.2-0.5.7.0'}

export DEVICE_PLUGIN_IMAGE=${DEVICE_PLUGIN_IMAGE:-'k8s-rdma-shared-device-plugin'}
export DEVICE_PLUGIN_REPO=${DEVICE_PLUGIN_REPO:-'harbor.mellanox.com/cloud-orchestration'}
export DEVICE_PLUGIN_VERSION=${DEVICE_PLUGIN_VERSION:-'latest'}

export SECONDARY_NETWORK_MULTUS_IMAGE=${SECONDARY_NETWORK_MULTUS_IMAGE:-'multus'}
export SECONDARY_NETWORK_MULTUS_REPO=${SECONDARY_NETWORK_MULTUS_REPO:-'harbor.mellanox.com/cloud-orchestration'}
export SECONDARY_NETWORK_MULTUS_VERSION=${SECONDARY_NETWORK_MULTUS_VERSION:-'latest'}

export SECONDARY_NETWORK_CNI_PLUGINS_IMAGE=${SECONDARY_NETWORK_CNI_PLUGINS_IMAGE:-'containernetworking-plugins'}
export SECONDARY_NETWORK_CNI_PLUGINS_REPO=${SECONDARY_NETWORK_CNI_PLUGINS_REPO:-'harbor.mellanox.com/cloud-orchestration'}
export SECONDARY_NETWORK_CNI_PLUGINS_VERSION=${SECONDARY_NETWORK_CNI_PLUGINS_VERSION:-'latest'}

export SECONDARY_NETWORK_IPAM_PLUGIN_IMAGE=${SECONDARY_NETWORK_IPAM_PLUGIN_IMAGE:-'whereabouts'}
export SECONDARY_NETWORK_IPAM_PLUGIN_REPO=${SECONDARY_NETWORK_IPAM_PLUGIN_REPO:-'harbor.mellanox.com/cloud-orchestration'}
export SECONDARY_NETWORK_IPAM_PLUGIN_VERSION=${SECONDARY_NETWORK_IPAM_PLUGIN_VERSION:-'latest'}

export NIC_OPERATOR_HELM_NAME=${NIC_OPERATOR_HELM_NAME:-'network-operator-helm-ci'}
export NIC_OPERATOR_CRD_NAME=${NIC_OPERATOR_CRD_NAME:-'nicclusterpolicies.mellanox.com'}

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