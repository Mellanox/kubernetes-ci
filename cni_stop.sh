#!/bin/bash -x

#TODO move to a common script

export LOGDIR=$WORKSPACE/logs
export ARTIFACTS=$WORKSPACE/artifacts

export KUBECONFIG=${KUBECONFIG:-/var/run/kubernetes/admin.kubeconfig}

mkdir -p $WORKSPACE
mkdir -p $LOGDIR
mkdir -p $ARTIFACTS

function delete_pods {
    kubectl delete pods --all
}

function stop_system_deployments {
    kubectl delete deployment -n kube-system --all
}

function stop_system_daemonset {
    for ds in $(kubectl -n kube-system get ds |grep kube|awk '{print $1}'); do
        kubectl -n kube-system delete ds $ds
    done
}

function stop_k8s_screen {
    for sc in $(screen -ls|grep multus|awk '{print $1}'); do
        screen -X -S $sc quit
    done
}

function asure_all_stoped {
    kill $(ps -ef |grep local-up-cluster.sh|grep $WORKSPACE|awk '{print $2}')
    kill $(pgrep sriovdp)
    kill $(ps -ef |grep kube |awk '{print $2}')
    kill -9 $(ps -ef |grep etcd|grep http|awk '{print $2}')
}

function delete_all_docker_container {
    docker stop $(docker ps -q)
    docker rm $(docker ps -a -q)
}

function delete_all_docker_images {
    docker rmi $(docker images -q)
}

function delete_chache_files {
    #delete network cache
    rm -rf /var/lib/cni/networks
}

function clean_tmp_workspaces {
    number_of_all_logs=$(ls -tr /tmp/ | grep k8s | wc -l)
    number_of_logs_to_keep=10
    let number_of_logs_to_clean="$number_of_all_logs"-"$number_of_logs_to_keep"
    echo "number of all logs $number_of_all_logs"
    echo "number of logs to clean $number_of_logs_to_clean"
    
    if [ "$number_of_logs_to_clean" -le 0 ]; then
            echo "no logs to clean"
    else
            logs_to_clean=$(ls -tr /tmp/ | grep k8s | head -n "$number_of_logs_to_clean")
            echo "Cleaning $number_of_logs_to_clean logs, it is these dirs:"
            echo "$logs_to_clean"
            for log in $logs_to_clean; do
                    echo "Removing /tmp/$log dir"
                    rm -rf /tmp/"$log"
            done
    fi
}

function reset_vfs_guids {
    let status=0

    if [[ -z "$(lspci |grep Mellanox | grep MT27800|head -n1|grep -i infini)" ]];then
        return 0
    fi

    unload_module mlx5_ib
    let status=$status+$?

    unload_module mlx5_core
    let status=$status+$?

    if [[ "$status" != "0" ]]; then
        return "$status"
    fi

    modprobe mlx5_core
    modprobe mlx5_ib
    sleep 10

    ifconfig ib0 up
    sleep 5
    ifconfig ib1 up
    sleep 5
    systemctl restart opensm

    return 0
}

function unload_module {
    local module=$1
    modprobe -r $module
    if [[ "$?" != "0" ]];then
       echo "ERROR: Failed to unload $module module!"
       return 1
    fi
}

let status=0

function load_inbox_drivers {
    modprobe mlx5_core
    modprobe ib_core
}

function delete_nic_operator_namespace {
    if [[ !  -f "$WORKSPACE/mellanox-network-operator/deploy/operator-ns.yaml" ]];then
        return 0
    fi
    nic_operator_namespace_file=$WORKSPACE/mellanox-network-operator/deploy/operator-ns.yaml
    operator_namespace=$(grep -E '^[ ]+name:' $nic_operator_namespace_file | head -n 1 | cut -d: -f2 | tr -d ' ')
    kubectl delete namespace $operator_namespace
    sleep 20
}


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

load_inbox_drivers

ps -ef |egrep "kube|local-up-cluster|etcd"

[ -d /var/lib/cni/sriov ] && rm -rf /var/lib/cni/sriov/*

reset_vfs_guids

let status=$status+$?

cp /tmp/kube*.log $LOGDIR
echo "All logs $LOGDIR"
echo "All confs $ARTIFACTS"
exit $status

