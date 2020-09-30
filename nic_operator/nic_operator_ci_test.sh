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

source ./common/common_functions.sh

test_pod_image='mellanox/rping-test'

function nic_policy_create {
    if [ $SRIOV_INTERFACE == 'auto_detect' ]; then
        export SRIOV_INTERFACE=$(ls -l /sys/class/net/ | grep $(lspci |grep Mellanox | grep -Ev 'MT27500|MT27520' | head -n1 | awk '{print $1}') | awk '{print $9}')
    fi

    nic_operator_dir=$WORKSPACE/mellanox-network-operator/deploy
    cr_file=$ARTIFACTS/ofed-rdma-nic-policy.yaml

    replace_placeholder REPLACE_INTERFACE $SRIOV_INTERFACE $cr_file
    kubectl create -f "$cr_file"
    
    cr_name=$(yaml_read metadata.name $cr_file)
    if [[ -z "$cr_name" ]]; then
        echo "Could not get the name of the example nicpolicy in $cr_file !!!"
        return 1
    fi
 
    operator_namespace=$(yaml_read metadata.name $nic_operator_dir/operator-ns.yaml)
    if [[ -z "$operator_namespace" ]]; then
        echo "Could not find operatore name space in $nic_operator_dir/operator-ns.yaml !!!"
        return 1
    fi

    nicpolicy_crd_name=$(yaml_read metadata.name $nic_operator_dir/crds/mellanox.com_nicclusterpolicies_crd.yaml)
    if [[ -z "$nicpolicy_crd_name" ]]; then
        echo "Could not find the CRD name in $nic_operator_dir/crds/mellanox.com_nicclusterpolicies_crd.yaml !!!"
        return 1
    fi
    
    cr_status=$(get_nic_policy_state $nicpolicy_crd_name $operator_namespace $cr_name)
    let stop=$(date '+%s')+$TIMEOUT
    d=$(date '+%s')
    while [ $d -lt $stop ]; do
        echo "Waiting for $cr_name to become ready"
        cr_status=$(get_nic_policy_state $nicpolicy_crd_name $operator_namespace $cr_name)
        if [ "$cr_status" == "ready" ]; then
	    echo "$cr_name is Ready!
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
    echo "Error $cr_name is not up"
    return 1
}

function get_nic_policy_state {
    local resource_definition_name=$1
    local policy_namespace=$2
    local resource_name=$3

    kubectl get "$resource_definition_name" -n "$policy_namespace" "$resource_name" -o json | grep '"state"' | cut -d: -f2 | tr -d ' "' | tail -n 1
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
    
    return $status
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
    
    echo "Creating example nic cluster policy/"
    
    nic_policy_create
    let status=status+$?
    if [ "$status" != 0 ]; then
        echo "Error: error in creating the example nic_policy."
        exit_code $status
    fi
    
    sleep 10
    
    test_ofed_drivers
    let status=status+$?
    if [ "$status" != 0 ]; then
        echo "Error: Ofed modules failed!"
        exit_code $status
    fi
    
    test_rdma_plugin
    let status=status+$?
    if [ "$status" != 0 ]; then
        echo "Error: RDMA device plugin testing Failed!"
        exit_code $status
    fi
    
    popd
    
    echo ""
    echo "All test succeeded!!"
    echo ""
}

main
exit_code $status

