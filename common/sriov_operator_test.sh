#!/bin/bash

source ./common/common_functions.sh

export RECLONE=${RECLONE:-true}
export WORKSPACE=${WORKSPACE:-/tmp/k8s_$$}
export LOGDIR=$WORKSPACE/logs
export ARTIFACTS=$WORKSPACE/artifacts
export TIMEOUT=${TIMEOUT:-600}
export POLL_INTERVAL=${POLL_INTERVAL:-10}

export default_vf_num="6"

function test_sriov_operator_e2e {
    pushd $WORKSPACE/sriov-network-operator

    # TODO: Sometimes the config daemon fails to discover the card
    # pfs, until the root cause is determined, deleting the
    # the config daemon pod would solve the issue.

    local config_daemon_info=$(kubectl get pods -A -l app=sriov-network-config-daemon | grep -v NAME)
    kubectl delete pod -n $(awk '{print $1}' <<< $config_daemon_info)\
        $(awk '{print $2}' <<< $config_daemon_info)


    make test-e2e-k8s
    let status=$status+$?
    if [ "$status" != 0 ]; then
        echo "Error: error in e2e testing!"
        popd
        return $status
    fi

    popd
}

set_sriov_operator_vfs_macs(){
    local vfs_num="${1:-$default_vf_num}"
    local interfaces=$@

    local last_index=0

    if [[ -z "${project}" ]];then
        echo "ERROR: Missing the project env variable!"
        return 1
    fi

    if [[ -z "$interfaces" ]];then
        echo "ERROR: PFs not provided for setting the macs!"
        return 1
    fi

    local old_IFS=$IFS
    IFS=' '

    local mac_index=0

    for interface in $interfaces;do
        for i in $(seq -s " " 0 $((vfs_num-1))); do
            sudo docker exec -t ${project}-worker ip link set $interface vf $i mac 00:22:00:11:22:$(printf '%02x' ${mac_index})
            pci=$(sudo docker exec -t ${project}-worker readlink /sys/class/net/$interface/device/virtfn$i | sed 's/..\///')
            pci=${pci//$'\r'/}
            sudo docker exec -t ${project}-worker bash -c "echo $pci > /sys/bus/pci/drivers/mlx5_core/unbind"
            sudo docker exec -t ${project}-worker bash -c "echo $pci > /sys/bus/pci/drivers/mlx5_core/bind"
            ((mac_index++))
        done
    done

    IFS=$pld_IFS
}

create_sriov_node_policy(){
    local policy_name=${1}
    local policy_namespace=${2}
    local resource_name=${3}

    render_sriov_node_policy "$policy_name" "" "$policy_namespace" "" "$resource_name"
    let status=$status+$?
    if [[ "$status" != "0" ]];then
        echo "Error: Failed to render the sriovnetworknodepolicy!"
        return $status
    fi

    kubectl create -f ${ARTIFACTS}/${policy_name}.yaml
    let status=$status+$?
    if [[ "$status" != "0" ]];then
        echo "Error: Failed to create the sriovnetworknodepolicy: ${policy_name}!"
        return $status
    fi


    sleep 120

    wait_sriov_state
    let status=$status+$?
    if [[ "$status" != "0" ]];then
        echo "Error: sriovnetworknodestate did not become Succeeded in $TIMEOUT!"
        return $status
    fi

    set_sriov_operator_vfs_macs "" "$(get_pfs_net_name ${project}-worker)"

    # Note(abdallahyas): Restarting the sriov network device plugin as workaround for the
    # issue with the operator latest image that it does not do that.
    # This should be removed after the issue is found and fixed, Issue
    # can be tracked in https://redmine.mellanox.com/issues/2748244

    echo "Restarting the sriov network device plugin pod"

    local device_plugin_pod_name="$(kubectl get pods -n ${policy_namespace} -o name | grep sriov-device-plugin | cut -d / -f 2)"

    kubectl delete pod -n "${policy_namespace}" "${device_plugin_pod_name}"

    return 0
}

delete_sriov_node_policy(){
    local policy_name=${1}
    local policy_namespace=${2}

    kubectl delete -f ${ARTIFACTS}/${policy_name}.yaml
    let status=$status+$?
    if [[ "$status" != "0" ]];then
        echo "Error: Failed to delete the sriovnetworknodepolicy: ${policy_name}!"
        return $status
    fi

    sleep 2

    wait_sriov_state
    let status=$status+$?
    if [[ "$status" != "0" ]];then
        echo "Error: sriovnetworknodestate did not become Succeeded in $TIMEOUT!"
        return $status
    fi
    return 0
}

create_sriov_network(){
    local network_name="${1}"
    local network_namespace=${2}
    local resource_name=${3}

    render_sriov_network "$network_name" "" "$network_namespace" "$resource_name"
    let status=$status+$?
    if [[ "$status" != "0" ]];then
        echo "Error: Failed to render the sriovnetwork!"
        return $status
    fi

    kubectl create -f ${ARTIFACTS}/${network_name}.yaml
    let status=$status+$?
    if [[ "$status" != "0" ]];then
        echo "Error: Failed to create the sriovnetwork: ${network_name}!"
        return $status
    fi
}

render_sriov_node_policy(){
    local policy_name="${1:-example-sriov-policy}"
    local file="${2:-${ARTIFACTS}/${policy_name}.yaml}"
    local policy_namespace=${3:-'sriov-network-operator'}
    local num_vfs=${4:-"${default_vf_num}"}
    local resource_name=${5:-'mlnxnics'}

    local pf_device_id=$(get_pf_device_id "${project}-worker")

    if [[ -f "$file" ]];then
        rm -f "$file"
    fi

    touch "$file"

    yaml_write "apiVersion" "sriovnetwork.openshift.io/v1" "$file"
    yaml_write "kind" "SriovNetworkNodePolicy" "$file"
    yaml_write "metadata.name" "${policy_name}" "$file"
    yaml_write "metadata.namespace" "${policy_namespace}" "$file"

    yaml_double_write "spec.nodeSelector[feature.node.kubernetes.io/network-sriov.capable]" true $file
    yaml_write "spec.resourceName" "$(echo $resource_name | tr - _)" $file
    yaml_write "spec.priority" "99" $file
    yaml_write "spec.mtu" "9000" $file
    yaml_write "spec.numVfs" "$num_vfs" $file
    yaml_write "spec.eSwitchMode" "legacy" $file
    yaml_double_write "spec.nicSelector.vendor" "15b3" $file
    yaml_double_write "spec.nicSelector.deviceID" "$pf_device_id" $file
    yaml_write "spec.deviceType" "netdevice" $file
    yaml_write "spec.isRdma" "true" $file
}

render_sriov_network(){
    local network_name="${1:-example-sriov-network}"
    local file="${2:-${ARTIFACTS}/${network_name}.yaml}"
    local network_namespace=${3:-'sriov-network-operator'}
    local resource_name=${4:-'mlnxnics'}

    if [[ -f "$file" ]];then
        rm -f "$file"
    fi

    touch "$file"

    yaml_write "apiVersion" "sriovnetwork.openshift.io/v1" "$file"
    yaml_write "kind" "SriovNetwork" "$file"
    yaml_write "metadata.name" "${network_name}" "$file"
    yaml_write "metadata.namespace" "${network_namespace}" "$file"

    yaml_write "spec.resourceName" "$(echo $resource_name | tr - _)" $file
    yaml_write "spec.networkNamespace" "default" $file

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
" "$file"
}

wait_sriov_state(){
    local state_namespace=${1:-'sriov-network-operator'}
    local sriov_node=${2:-${project}-worker}
    local wanted_state=${3:-'Succeeded'}

    local status_key="status.syncStatus"

    sriov_state="$(kubectl get sriovnetworknodestates -n ${state_namespace} $sriov_node -o yaml | yq r - $status_key)"
    let stop=$(date '+%s')+$TIMEOUT
    d=$(date '+%s')
    while [ $d -lt $stop ]; do
        echo "Waiting for sriovnetworknodestate of $sriov_node to become $wanted_state"
        sriov_state="$(kubectl get sriovnetworknodestates -n ${state_namespace} $sriov_node -o yaml | yq r - $status_key)"
        if [[ "$sriov_state" == "$wanted_state" ]]; then
            echo "sriovnetworknodestate is $wanted_state!"
            return 0
        fi
        sleep $POLL_INTERVAL
    done
    kubectl describe sriovnetworknodestates -n ${state_namespace} $sriov_node
    echo "Error sriovnetworknodestate is not $wanted_state"
    return 1
}

