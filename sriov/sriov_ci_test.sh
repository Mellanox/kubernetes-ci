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

export KUBECONFIG=${KUBECONFIG:-/etc/kubernetes/admin.conf}
export K8S_RDMA_SHARED_DEV_PLUGIN=${K8S_RDMA_SHARED_DEV_PLUGIN:-master}

function pod_create {
    pod_name="$1"
    sriov_pod=$ARTIFACTS/"$pod_name"
    cat > $sriov_pod <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: $pod_name
  annotations:
    k8s.v1.cni.cncf.io/networks: sriov-rdma-net
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
          mellanox.com/sriov_rdma: '1'
        limits:
          mellanox.com/sriov_rdma: '1'
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

function test_pods {
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
#   screen -S rping_server -d -m bash -x -c "kubectl exec -it $POD_NAME_1 -- rping -svd"
#   kubectl exec -it $POD_NAME_2 -- sh -c "rping -cvd -a $ip_1 -C 1 > /dev/null 2>&1"
#   let status=status+$?
#
#   if [ "$status" != 0 ]; then
#       echo "Error: rping failed"
#       return $status
#   fi

    echo "all tests succeeded!!" 

    return $status
 }

function exit_code {
    rc="$1"
    echo "All logs $LOGDIR"
    echo "All confs $ARTIFACTS"
    echo "To stop K8S run # WORKSPACE=${WORKSPACE} ./cni_stop.sh"
    exit $status
}

status=0

pushd $WORKSPACE

echo "Creating pod test-pod-1"
pod_create 'test-pod-1'
let status=status+$?

if [ "$status" != 0 ]; then
    echo "Error: error in creating the first pod"
    exit_code $status
fi

echo "Creating pod test-pod-2"
pod_create 'test-pod-2'
let status=status+$?

if [ "$status" != 0 ]; then
    echo "Error: error in creating the second pod"
    exit_code $status
fi

test_pods 'test-pod-1' 'test-pod-2'

let status=status+$?

if [ "$status" != 0 ]; then
    echo "Error: error in testing the pods"
    exit_code $status
fi

exit_code $status
