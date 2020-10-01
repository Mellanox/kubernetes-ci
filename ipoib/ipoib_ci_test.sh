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

source ./common/common_functions.sh

test_pod_image='mellanox/rping-test'

function pod_create_server {
    POD_NAME=$1
    local resource=$2

    if [[ -z "$resource" ]]; then
        resource="rdma/hca_shared_devices_a"
    fi
    
    cd $ARTIFACTS
    curl https://raw.githubusercontent.com/Mellanox/k8s-rdma-shared-dev-plugin/${K8S_RDMA_SHARED_DEV_PLUGIN}/example/test-hca-pod.yaml -o $ARTIFACTS/test-hca-pod.yaml
    patch <<EOF
--- test-hca-pod.yaml	2020-03-16 19:43:32.002735348 +0200
+++ test-hca-pod.yaml	2020-03-16 19:37:05.122828220 +0200
@@ -2,6 +2,8 @@ apiVersion: v1
 kind: Pod
 metadata:
   name: mofed-test-pod
+  annotations:
+    k8s.v1.cni.cncf.io/networks: ipoib-network
 spec:
   restartPolicy: OnFailure
   containers:
@@ -18,4 +20,5 @@ spec:
     - -c
     - |
       ls -l /dev/infiniband /sys/class/net
+      ib_write_bw -d mlx5_0
       sleep 1000000
EOF

    mv $ARTIFACTS/test-hca-pod.yaml $ARTIFACTS/${POD_NAME}.yaml
    sed -i "s/name: mofed-test-pod/name: ${POD_NAME}/g" $ARTIFACTS/${POD_NAME}.yaml
    sed -i "s;image: .*;image: $test_pod_image;g" $ARTIFACTS/${POD_NAME}.yaml
    yaml_write spec.containers[0].resources.limits "" $ARTIFACTS/${POD_NAME}.yaml
    yaml_write spec.containers[0].resources.limits.${resource} 1 $ARTIFACTS/${POD_NAME}.yaml
    
    return $?
}


function pod_create_client {
    POD_NAME=$1
    local resource=$2

    if [[ -z "$resource" ]]; then
        resource="rdma/hca_shared_devices_a"
    fi

    cd $ARTIFACTS
    curl https://raw.githubusercontent.com/Mellanox/k8s-rdma-shared-dev-plugin/${K8S_RDMA_SHARED_DEV_PLUGIN}/example/test-hca-pod.yaml -o $ARTIFACTS/test-hca-pod.yaml
    patch <<EOF
--- test-hca-pod.yaml	2020-03-16 19:43:32.002735348 +0200
+++ test-hca-pod.yaml	2020-03-16 19:37:05.122828220 +0200
@@ -2,6 +2,8 @@ apiVersion: v1
 kind: Pod
 metadata:
   name: mofed-test-pod
+  annotations:
+    k8s.v1.cni.cncf.io/networks: ipoib-network
 spec:
   restartPolicy: OnFailure
   containers:
EOF

    mv $ARTIFACTS/test-hca-pod.yaml $ARTIFACTS/${POD_NAME}.yaml
    sed -i "s/name: mofed-test-pod/name: ${POD_NAME}/g" $ARTIFACTS/${POD_NAME}.yaml
    sed -i "s;image: .*;image: $test_pod_image;g" $ARTIFACTS/${POD_NAME}.yaml
    yaml_write spec.containers[0].resources.limits "" $ARTIFACTS/${POD_NAME}.yaml
    yaml_write spec.containers[0].resources.limits.${resource} 1 $ARTIFACTS/${POD_NAME}.yaml
    return $?
}


function pod_start {
    /usr/local/bin/kubectl create -f $ARTIFACTS/${POD_NAME}.yaml

    pod_status=$(/usr/local/bin/kubectl get pods | grep $POD_NAME |awk '{print $3}')
    let stop=$(date '+%s')+$TIMEOUT
    d=$(date '+%s')
    while [ $d -lt $stop ]; do
        echo "Waiting for pod $POD_NAME to became Running"
        pod_status=$(/usr/local/bin/kubectl get pods | grep $POD_NAME |awk  '{print $3}')
        if [ "$pod_status" == "Running" ]; then
            return 0
        fi
        /usr/local/bin/kubectl get pods | grep $POD_NAME
        /usr/local/bin/kubectl describe pod $POD_NAME
        sleep ${POLL_INTERVAL}
        d=$(date '+%s')
    done
    echo "Failed to bring up ${POD_NAME}"
    return 1
}


function test_pod_resources {
    local status=0
    POD_NAME=$1

    echo "Checking net1 for address network $NETWORK in pod $POD_NAME"
    /usr/local/bin/kubectl exec -i $POD_NAME -- ip a
    /usr/local/bin/kubectl exec -i $POD_NAME ifconfig net1

    n=$(/usr/local/bin/kubectl exec -i ${POD_NAME} ifconfig net1 | egrep "$NETWORK|infiniband"|wc -l)
    if [ $n -ne 2 ]; then
	status=1
        echo "Failed to recognize net1 as infiniband interface with $NETWORK in pod $POD_NAME"
    else
        echo "Passed to recognize net1 as infiniband interface with $NETWORK in pod $POD_NAME"
    fi
    /usr/local/bin/kubectl exec -i ${POD_NAME} ls /dev/infiniband/
    let status=status+$?

    return $status
}

function test_pods_connectivity {
    local status=0
    POD_NAME_1=$1
    POD_NAME_2=$2

    ip_1=$(/usr/local/bin/kubectl exec -i ${POD_NAME_1} ifconfig net1|grep inet|awk '{print $2}')
    /usr/local/bin/kubectl exec -i ${POD_NAME_1} ifconfig net1
    echo "${POD_NAME_1} has ip ${ip_1}"

    ip_2=$(/usr/local/bin/kubectl exec -i ${POD_NAME_2} ifconfig net1|grep inet|awk '{print $2}')
    /usr/local/bin/kubectl exec -i ${POD_NAME_2} ifconfig net1
    echo "${POD_NAME_2} has ip ${ip_2}"

    /usr/local/bin/kubectl exec -i ${POD_NAME_1} ls /dev/infiniband/
    let status=status+$?

    /usr/local/bin/kubectl exec -i ${POD_NAME_2} ls /dev/infiniband/
    let status=status+$?

    /usr/local/bin/kubectl exec ${POD_NAME_2} -- bash -c "ib_write_bw -d mlx5_0 -D 10 ${ip_1}"
    let status=status+$?

    return $status
 }

function delete_pod {
    local pod_name="$1"
    kubectl delete -f $ARTIFACTS/${pod_name}.yaml
    sleep 20
}

function test_pods {
    POD_NAME_1=$1
    POD_NAME_2=$2
    RESOURCE="$3"

    local local_status=0

    echo "Creating pod $POD_NAME_1 for ib_write_bw server using $RESOURCE"
    pod_create_server $POD_NAME_1 "$RESOURCE"
    let local_status=local_status+$?
    if [ $local_status -ne 0 ]; then
        echo "Failed to get $POD_NAME_1 yaml!"
        return "$local_status"
    fi
    
    pod_start "$POD_NAME_1"
    let local_status=local_status+$?
    if [ $local_status -ne 0 ]; then
        echo "Failed to run $POD_NAME_1 !"
        return "$local_status"
    fi
    
    
    echo "Creating pod $POD_NAME_2 as client using $RESOURCE"
    pod_create_client "$POD_NAME_2" "$RESOURCE"
    let local_status=local_status+$?
    if [ $local_status -ne 0 ]; then
        echo "Failed to get $POD_NAME_2 yaml !"
        return "$local_status"
    fi

    pod_start "$POD_NAME_2"
    let local_status=local_status+$?
    if [ $local_status -ne 0 ]; then
        echo "Failed to run $POD_NAME_2 !"
        return "$local_status"
    fi

    test_pods_connectivity "$POD_NAME_1" "$POD_NAME_2"
    let local_status=local_status+$?
    if [ $local_status -ne 0 ]; then
        echo "Failed to test pods!"
    fi

    delete_pod "$POD_NAME_1"
    delete_pod "$POD_NAME_2"

    return "$local_status"
}

function exit_script {
    local local_rc="$1"
    echo "All logs $LOGDIR"
    echo "All confs $ARTIFACTS"
    echo "To stop K8S run # WORKSPACE=${WORKSPACE} ./cni_stop.sh"
    exit $local_rc
}

pushd $WORKSPACE

status=0

test_pods legacy-test-pod1 legacy-test-pod2 rdma/hca_shared_devices_a

let status=status+$?
if [ $status -ne 0 ]; then
    echo "Failed to test legacy devices mode !"
    exit_script "$status"
fi


test_pods selectors-test-pod1 selectors-test-pod2 rdma/hca_shared_devices_b

let status=status+$?
if [ $status -ne 0 ]; then
    echo "Failed to test selector devices mode !"
    exit_script "$status"
fi

echo ""
echo "All tests succeeded!"
echo ""

popd
exit_script "$status"
