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

pushd $WORKSPACE

test_pod_image='mellanox/rping-test'

function pod_create_server {
    POD_NAME=$1
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
    return $?
}


function pod_create_client {
    POD_NAME=$1
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


function test_pod {
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

function test_pods {
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

status=0
echo "Creating pod mofed-test-pod2 for ib_write_bw server"
pod_create_server mofed-test-pod1
let status=status+$?
if [ $status -ne 0 ]; then
    echo "Failed to get mofed-test-pod1 yaml!"
    exit "$status"
fi

pod_start mofed-test-pod1
let status=status+$?
if [ $status -ne 0 ]; then
    echo "Failed to run mofed-test-pod1!"
    exit "$status"
fi


echo "Creating pod mofed-test-pod2"
pod_create_client mofed-test-pod2
let status=status+$?
if [ $status -ne 0 ]; then
    echo "Failed to get mofed-test-pod2 yaml!"
    exit "$status"
fi

pod_start mofed-test-pod2
let status=status+$?
if [ $status -ne 0 ]; then
    echo "Failed to run mofed-test-pod2!"
    exit "$status"
fi


test_pods mofed-test-pod1 mofed-test-pod2
let status=status+$?
if [ $status -ne 0 ]; then
    echo "Failed to test pods!"
    exit "$status"
fi



echo "All logs $LOGDIR"
echo "All confs $ARTIFACTS"
echo "To stop K8S run # WORKSPACE=${WORKSPACE} ./cni_stop.sh"
exit $status
