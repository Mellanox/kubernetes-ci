#!/bin/bash

export WORKSPACE=${WORKSPACE:-/tmp/k8s_$$}
export LOGDIR=$WORKSPACE/logs
export ARTIFACTS=$WORKSPACE/artifacts

export GOROOT=${GOROOT:-/usr/local/go}
export GOPATH=${WORKSPACE}
export PATH=/usr/local/go/bin/:$GOPATH/src/k8s.io/kubernetes/third_party/etcd:$PATH
export TIMEOUT=${TIMEOUT:-300}

export POLL_INTERVAL=${POLL_INTERVAL:-10}
export NETWORK=${NETWORK:-'192.168'}

export KUBECONFIG=${KUBECONFIG:-/var/run/kubernetes/admin.kubeconfig}
export K8S_RDMA_SHARED_DEV_PLUGIN=${K8S_RDMA_SHARED_DEV_PLUGIN:-master}

export SRIOV_INTERFACE=${SRIOV_INTERFACE:-auto_detect}

mkdir -p $WORKSPACE
mkdir -p $LOGDIR
mkdir -p $ARTIFACTS

starting_guids=""
after_creation_guids=""
after_deletion_guids=""

pushd $WORKSPACE

function pod_create {
    pod_name="$1"
    sriov_pod=$ARTIFACTS/"$pod_name"
    cat > $sriov_pod <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: $pod_name
  annotations:
    k8s.v1.cni.cncf.io/networks: ib-sriov-crd
spec:
  containers:
    - name: rdma-app
      image: mmdh/rping-test
      imagePullPolicy: IfNotPresent
      securityContext:
        capabilities:
          add: [ "IPC_LOCK" ]
      command: [ "/bin/bash", "-c", "--" ]
      args: [ "while true; do sleep 300000; done;" ]
      resources:
        requests:
          mellanox.com/mlnx_sriov_rdma_ib: '1'
        limits:
          mellanox.com/mlnx_sriov_rdma_ib: '1'
EOF
    kubectl get pods
    kubectl delete -f $sriov_pod 2>&1|tee > /dev/null
    sleep ${POLL_INTERVAL}
    kubectl create -f $sriov_pod

    pod_status=$(kubectl get pods | grep "$pod_name" |awk  '{print $3}')
    let stop=$(date '+%s')+$TIMEOUT
    d=$(date '+%s')
    while [ $d -lt $stop ]; do
        echo "Waiting for pod to became Running"
        pod_status=$(kubectl get pods | grep "$pod_name" |awk  '{print $3}')
        if [ "$pod_status" == "Running" ]; then
            sleep 10
            return 0
        elif [ "$pod_status" == "UnexpectedAdmissionError" ]; then
            kubectl delete -f $sriov_pod
            sleep ${POLL_INTERVAL}
            kubectl create -f $sriov_pod
        fi
        kubectl get pods | grep "$pod_name"
        kubectl describe pod "$pod_name"
        sleep ${POLL_INTERVAL}
        d=$(date '+%s')
    done
    echo "Error $pod_name is not up"
    return 1
}

function test_pods_connectivity {
    local status=0
    POD_NAME_1=$1
    POD_NAME_2=$2

    ip_1=$(/usr/local/bin/kubectl exec -i ${POD_NAME_1} -- ifconfig net1|grep inet|awk '{print $2}')
    /usr/local/bin/kubectl exec -i ${POD_NAME_1} -- ifconfig net1
    echo "${POD_NAME_1} has ip ${ip_1}"

    ip_2=$(/usr/local/bin/kubectl exec -i ${POD_NAME_2} -- ifconfig net1|grep inet|awk '{print $2}')
    /usr/local/bin/kubectl exec -i ${POD_NAME_2} -- ifconfig net1
    echo "${POD_NAME_2} has ip ${ip_2}"

    /usr/local/bin/kubectl exec ${POD_NAME_2} -- bash -c "ping $ip_1 -c 1 >/dev/null 2>&1"
    let status=status+$?

    if [ "$status" != 0 ]; then
        echo "Error: There is no connectivity between the pods"
        return $status
    fi

    #TOFIX: rping test need to be fixed
#    screen -S rping_server -d -m bash -x -c "kubectl exec $POD_NAME_1 -- rping -svd"
#    screen -list
#    sleep 10
#    kubectl exec -it $POD_NAME_2 -- sh -c "rping -cvd -a $ip_1 -C 1 > /dev/null 2>&1"
#    let status=status+$?
#
#    if [ "$status" != 0 ]; then
#        echo "Error: rping failed"
#        return $status
#    fi

    return $status
 }

function delete_pods {
    kubectl delete pods --all
    sleep 10
}

function print_vfs_guids {
    local guids="$1"
    local message="$2"

    echo ""
    echo "$message"
    echo "$guids"
}

function test_guids_reseted {
    local guids=$1
    for guid in $guids; do
        echo "guid is: $guid"
        if [[ "$guid" != '00:00:00:00:00:00:00:00' ]];then
            if [[ "$guid" != 'ff:ff:ff:ff:ff:ff:ff:ff' ]]; then
                echo "ERROR: A VF GUID was not reset after pod deletion and its value is $guid !"
                return 1
            fi
        fi
    done
}

function get_vfs_guids {
    interface="$1"
    ip link show  "$interface" | grep vf | grep -o 'NODE_GUID [0-9a-z:]*' | cut -d' ' -f 2
}


function exit_code {
    rc="$1"
    echo "All logs $LOGDIR"
    echo "All confs $ARTIFACTS"
    echo "To stop K8S run # WORKSPACE=${WORKSPACE} ./cni_stop.sh"
    exit $status
}

function test_pods {
    status=0

    starting_guids=$(get_vfs_guids $SRIOV_INTERFACE)
    print_vfs_guids "$starting_guids" "VFs GUIDs before the test are:"

    echo "Creating pod test-pod-1"
    pod_create 'test-pod-1'
    let status=status+$?
    
    if [ "$status" != 0 ]; then
        echo "Error: error in creating the first pod"
        return $status
    fi
    
    echo "Creating pod test-pod-2"
    pod_create 'test-pod-2'
    let status=status+$?
    
    if [ "$status" != 0 ]; then
        echo "Error: error in creating the second pod"
        return $status
    fi

    after_creation_guids=$(get_vfs_guids $SRIOV_INTERFACE)
    print_vfs_guids "$after_creation_guids" "Pods created successfully! VFs GUIDs after pods creation are:"
    
    test_pods_connectivity 'test-pod-1' 'test-pod-2'
     
    let status=status+$?

    echo "Testing GUID reseted after pod deletion."

    delete_pods

    after_deletion_guids=$(get_vfs_guids $SRIOV_INTERFACE)
    print_vfs_guids "$after_deletion_guids" "Pods deleted! Vfs GUIDs after deletion are:"

    test_guids_reseted "$after_deletion_guids"

    let status=status+$?

     if [ "$status" != 0 ]; then
        echo "Error: error in testing the pods"
        return $status
     fi

     echo "all tests succeeded!!"

     return $status
    
}

function main {
    status=0

    if [ $SRIOV_INTERFACE == 'auto_detect' ]; then
        export SRIOV_INTERFACE=$(ls -l /sys/class/net/ | grep $(lspci |grep Mellanox | grep -Ev 'MT27500|MT27520'| head -n1 | awk '{print $1}') | awk '{print $9}')
    fi

    test_pods

    let status=status+$?

    echo ""
    echo "GUIDs durring the test were:"
    echo "Starting GUIDs:            $(echo $starting_guids)"
    echo "After pods creation GUIDs: $(echo $after_creation_guids)"
    echo "After pods deletion GUIDs: $(echo $after_deletion_guids)"
    echo ""

    if [[ $status != "0" ]]; then
        return $status
    fi
}

main

let status=status+$?
if [[ $status != "0" ]]; then
    exit_code $status
fi

exit_code $status
