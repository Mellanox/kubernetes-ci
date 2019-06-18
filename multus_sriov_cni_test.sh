#!/bin/bash

export WORKSPACE=${WORKSPACE:-/tmp/k8s_$$}
export LOGDIR=$WORKSPACE/logs
export ARTIFACTS=$WORKSPACE/artifacts

export GOROOT=${GOROOT:-/usr/local/go}
export GOPATH=${WORKSPACE}
export PATH=/usr/local/go/bin/:$GOPATH/src/k8s.io/kubernetes/third_party/etcd:$PATH

export CNI_BIN_DIR=${CNI_BIN_DIR:-/opt/cni/bin/}
export CNI_CONF_DIR=${CNI_CONF_DIR:-/etc/cni/net.d/}
export ALLOW_PRIVILEGED=${ALLOW_PRIVILEGED:-true}
export NET_PLUGIN=${NET_PLUGIN:-cni}
export TIMEOUT=${TIMEOUT:-300}

export KUBECONFIG=${KUBECONFIG:-/var/run/kubernetes/admin.kubeconfig}

pushd $WORKSPACE


function pod_create {
    sriov_pod=$ARTIFACTS/sriov_pod.yaml
    cat > $sriov_pod <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: mofed-test-pod-1
  annotations:
    k8s.v1.cni.cncf.io/networks: sriov-net1
spec:
  restartPolicy: OnFailure
  containers:
    - image: alpine
      name: alpine
      imagePullPolicy: IfNotPresent
      resources:
        requests:
          intel.com/sriov: 3
        limits:
          intel.com/sriov: 3
      command:
        - sh
        - -c
        - |
          ls -l /sys/class/net
          sleep 1000000
EOF
    kubectl get pods
    kubectl create -f $sriov_pod

    pod_status=$(kubectl get pods | grep mofed-test-pod-1 |awk  '{print $3}')
    let stop=$(date '+%s')+$TIMEOUT
    d=$(date '+%s')
    while [ $d -lt $stop ]; do
        echo "Waiting for pod to became Running"
        pod_status=$(kubectl get pods | grep mofed-test-pod-1 |awk  '{print $3}')
        if [ $pod_status = 'Running' ]; then
            return 0
        fi
        kubectl get pods | grep mofed-test-pod-1
        kubectl describe pod mofed-test-pod-1
        sleep 5
        d=$(date '+%s')
    done
    echo "Error mofed-test-pod-1 is not up"
    return 1
}


function test_pod {
    kubectl exec -i mofed-test-pod-1 -- ip a
    return $?
}


pod_create
test_pod
status=$?
echo "All logs $LOGDIR"
echo "All confs $ARTIFACTS"
echo "To stop K8S run # WORKSPACE=${WORKSPACE} ./multus_sriov_cni_stop.sh"
exit $status
