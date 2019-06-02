#!/bin/bash -x

export RECLONE=${RECLONE:-true}
export WORKSPACE=${WORKSPACE:-/tmp/k8s_$$}
export LOGDIR=$WORKSPACE/logs
export ARTIFACTS=$WORKSPACE/artifacts

export PATH=/usr/local/go/bin/:/opt/cni/bin/:/home_stack/cni/cni/cnitool/$PATH
export CNI_PATH=/opt/cni/bin/

MULTUS_CNI_BRANCH=${MULTUS_CNI_BRANCH:-master}
MULTUS_CNI_REPO=${MULTUS_CNI_REPO:-https://github.com/intel/multus-cni}

SRIOV_CNI_BRANCH=${SRIOV_CNI_BRANCH:-master}
SRIOV_CNI_REPO=${SRIOV_CNI_REPO:-https://github.com/intel/sriov-cni}

PLUGINS_BRANCH=${PLUGINS_BRANCH:-master}
PLUGINS_REPO=${PLUGINS_REPO:-https://github.com/containernetworking/plugins.git}

SRIOV_NETWORK_DEVICE_PLUGIN_REPO=${SRIOV_NETWORK_DEVICE_PLUGIN_REPO:-https://github.com/intel/sriov-network-device-plugin}
SRIOV_NETWORK_DEVICE_PLUGIN_BRANCH=${SRIOV_NETWORK_DEVICE_PLUGIN_BRANCH:-remotes/origin/feature/device_selectors}

export GOROOT=${GOROOT:-/usr/local/go}
export GOPATH=${WORKSPACE}
export CNI_BIN_DIR=${CNI_BIN_DIR:-/opt/cni/bin/}
export CNI_CONF_DIR=${CNI_CONF_DIR:-/etc/cni/net.d/}
export ALLOW_PRIVILEGED=${ALLOW_PRIVILEGED:-true}
export NET_PLUGIN=${NET_PLUGIN:-cni}

export KUBE_ENABLE_CLUSTER_DNS=${KUBE_ENABLE_CLUSTER_DNS:-false}
export API_HOST=$(hostname).$(hostname -y)
export API_HOST_IP=$(hostname -I | awk '{print $1}')
export KUBECONFIG=${KUBECONFIG:-/var/run/kubernetes/admin.kubeconfig}

#TODO add autodiscovering
export MACVLAN_INTERFACE=${MACVLAN_INTERFACE:-eno1}
export SRIOV_INTERFACE=${SRIOV_INTERFACE:-enp3s0f0}

echo "Working under $WORKSPACE folder"
mkdir -p $WORKSPACE
mkdir -p $LOGDIR
mkdir -p $ARTIFACTS
mkdir -p $CNI_CONF_DIR
mkdir -p $CNI_BIN_DIR

pushd $WORKSPACE


function configure_multus {
    echo "Configure Multus"
    interface=$1

    kubectl delete -f $WORKSPACE/multus-cni/images/multus-daemonset.yml
    kubectl create -f $WORKSPACE/multus-cni/images/multus-daemonset.yml
    sleep 60
    cat > $CNI_CONF_DIR/00-multus.conf <<EOF
{
    "name": "multus-cni-network",
    "type": "multus",
    "capabilities": {
        "portMappings": true
    },
    "delegates": [
        {
            "cniVersion": "0.3.0",
            "name": "macvlan-network",
            "type": "macvlan",
            "master": "$interface",
            "mode": "bridge",
            "ipam": {
                "type": "host-local",
                "subnet": "192.168.1.0/24",
                "rangeStart": "192.168.1.200",
                "rangeEnd": "192.168.1.216",
                "routes": [{"dst": "0.0.0.0/0"}],
                "gateway": "192.168.1.1"
            }
        }
    ],
    "logFile": "$LOGDIR/multus.log",
    "logLevel": "debug",
    "kubeconfig": "$KUBECONFIG"
}
EOF
    cp $CNI_CONF_DIR/00-multus.conf $ARTIFACTS
    return $?
}


function download_cni {

    if ! $RECLONE ; then
        return 0
    fi

    echo "Download $MULTUS_CNI_REPO"
    git clone $MULTUS_CNI_REPO $WORKSPACE/multus-cni
    cd $WORKSPACE/multus-cni
    git checkout $MULTUS_CNI_BRANCH
    git log -p -1 > $ARTIFACTS/multus-cni.txt
    cd -

    echo "Download $SRIOV_CNI_REPO"
    git clone $SRIOV_CNI_REPO $WORKSPACE/sriov-cni
    pushd $WORKSPACE/sriov-cni
    git checkout $SRIOV_CNI_BRANCH
    git log -p -1 > $ARTIFACTS/sriov-cni.txt
    popd

    echo "Download $PLUGINS_REPO"
    git clone $PLUGINS_REPO $WORKSPACE/plugins
    pushd $WORKSPACE/plugins
    git checkout $PLUGINS_BRANCH
    git log -p -1 > $ARTIFACTS/plugins.txt
    ./build_linux.sh
    popd

    echo "Download $SRIOV_NETWORK_DEVICE_PLUGIN_REPO"
    git clone $SRIOV_NETWORK_DEVICE_PLUGIN_REPO $WORKSPACE/sriov-network-device-plugin
    pushd $WORKSPACE/sriov-network-device-plugin
    git checkout $SRIOV_NETWORK_DEVICE_PLUGIN_BRANCH
    git log -p -1 > $ARTIFACTS/sriov-network-device-plugin.txt
    make build
    popd
    mkdir -p /etc/pcidp/
    cat > /etc/pcidp/config.json <<EOF
{
    "resourceList": [{
        "resourceName": "sriov",
        "selectors": {
                "vendors": ["15b3"],
                "devices": ["1018"],
                "drivers": ["mlx5_core"]
            }
    }
    ]
}
EOF
    cp /etc/pcidp/config.json $ARTIFACTS
    return 0
}


function pod_create {
    cat > /tmp/sriov_pod.yaml <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: mofed-test-pod-1
  annotations:
    k8s.v1.cni.cncf.io/networks: sriov-net1
spec:
  restartPolicy: OnFailure
  containers:
    - image: mellanox/mlnx_ofed_linux-4.4-1.0.0.0-centos7.4
      name: mofed-test-ctr
      imagePullPolicy: IfNotPresent
      securityContext:
        capabilities:
          add: ["IPC_LOCK"]
      resources:
        requests:
          intel.com/sriov: 2
        limits:
          intel.com/sriov: 2
      command:
        - sh
        - -c
        - |
          ls -l /dev/infiniband /sys/class/net
          sleep 1000000
EOF
    cp /tmp/sriov_pod.yaml $ARTIFACTS
    kubectl delete -f /tmp/sriov_pod.yaml
    kubectl create -f /tmp/sriov_pod.yaml

    #TODO add timeout
    pod_status=$(kubectl get pods | grep mofed-test-pod-1 |awk  '{print $3}')
    while [ $pod_status != 'Running' ]; do
        echo "Waiting for pod to became Running"
        pod_status=$(kubectl get pods | grep mofed-test-pod-1 |awk  '{print $3}')
        sleep 30
    done
    kubectl describe pod mofed-test-pod-1
    return $?
}


function test_pod {
    kubectl exec -i mofed-test-pod-1 -- ip a
    return $?
}


function clear_vfs {
    echo 0 > /sys/class/net/$SRIOV_INTERFACE/device/sriov_numvfs
    echo 4 > /sys/class/net/$SRIOV_INTERFACE/device/sriov_numvfs
}


function install_k8s {
    echo "Stopping previous K8S run"
    #TODO clean on exit
    kill $(ps -ef |grep kube |awk '{print $2}')
    go get -d k8s.io/kubernetes
    cd $GOPATH/src/k8s.io/kubernetes
    git log -p -1 > $ARTIFACTS/kubernetes.txt
    make
    go get -u github.com/tools/godep
    go get -u github.com/cloudflare/cfssl/cmd/...
    $GOPATH/src/k8s.io/kubernetes/hack/install-etcd.sh
    export PATH="$GOPATH/src/k8s.io/kubernetes/third_party/etcd:${PATH}"

    $GOPATH/src/k8s.io/kubernetes/hack/local-up-cluster.sh 2>&1|tee > $LOGDIR/kubernetes.log &
    k8s_pid=$!
    echo "K8S is running with pid=$k8s_pid"
    kubectl get pods
    rc=$?
    #TODO add timeout and better k8s up check
    while [ $rc -ne 0 ]; do
       echo "Wait until K8S is up"
       kubectl get pods
       rc=$?
       sleep 5
    done
    return $k8s_pid
}


#TODO add check prereqs
#TODO add docker image mellanox/mlnx_ofed_linux-4.4-1.0.0.0-centos7.4 presence


clear_vfs
download_cni

K8S_PID=$(install_k8s)
configure_multus $MACVLAN_INTERFACE
kill $(pgrep sriovdp)
nohup $WORKSPACE/sriov-network-device-plugin/build/sriovdp -logtostderr 10 2>&1|tee > $LOGDIR/sriovdp.log &

kubectl delete -f $WORKSPACE/sriov-network-device-plugin/deployments/sriov-crd.yaml
kubectl create -f $WORKSPACE/sriov-network-device-plugin/deployments/sriov-crd.yaml
pod_create
test_pod
status=$?
echo "All logs $LOGDIR"
echo "All confs $ARTIFACTS"
exit $status
