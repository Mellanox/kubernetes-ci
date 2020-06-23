#!/bin/bash 
set -x

export LOGDIR=$WORKSPACE/logs
export ARTIFACTS=$WORKSPACE/artifacts

export KUBECONFIG=${KUBECONFIG:-/var/run/kubernetes/admin.kubeconfig}

source ./clean_common.sh

mkdir -p $WORKSPACE
mkdir -p $LOGDIR
mkdir -p $ARTIFACTS

function delete_nic_operator_namespace {
    nic_operator_namespace_file=$WORKSPACE/mellanox-network-operator/deploy/operator-ns.yaml
    kubectl delete -f $nic_operator_namespace_file
    sleep 20
}

function main {
   
    delete_pods
    
    delete_nic_operator_namespace
    
    stop_system_deployments
    
    stop_system_daemonset
    
    stop_k8s_screen
    
    asure_all_stoped
    
    delete_chache_files
    
    delete_all_docker_container
    
    delete_all_docker_images
    
    clean_tmp_workspaces
    
    load_core_drivers                                                                                                                                                                                                                            
    let status=$status+$?
    
    cp /tmp/kube*.log $LOGDIR
    echo "All logs $LOGDIR"
    echo "All confs $ARTIFACTS"
}

main

