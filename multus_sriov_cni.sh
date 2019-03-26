#!/bin/bash -ex

WORKSPACE=${WORKSPACE:-/tmp/k8s_$$}
LOGDIR=$WORKSPACE/logs
ARTIFACTS=$WORKSPACE/artifacts

PATH=/usr/local/go/bin/:/opt/cni/bin/:/home_stack/cni/cni/cnitool/$PATH
CNI_PATH=/opt/cni/bin/ 

MULTUS_CNI_BRANCH=${MULTUS_CNI_BRANCH:-master}
MULTUS_CNI_REPO=${MULTUS_CNI_REPO:-https://github.com/intel/multus-cni}

SRIOV_CNI_BRANCH=${SRIOV_CNI_BRANCH:-master}
SRIOV_CNI_REPO=${SRIOV_CNI_REPO:-https://github.com/intel/sriov-cni}

PLUGINS_BRANCH=${PLUGINS_BRANCH:-master}
PLUGINS_REPO=${PLUGINS_REPO:-https://github.com/containernetworking/plugins.git}

SRIOV_NETWORK_DEVICE_PLUGIN_REPO=${SRIOV_NETWORK_DEVICE_PLUGIN_REPO:-https://github.com/intel/sriov-network-device-plugin}
SRIOV_NETWORK_DEVICE_PLUGIN_BRANCH=${SRIOV_NETWORK_DEVICE_PLUGIN_BRANCH:-remotes/origin/feature/device_selectors}

GOROOT=${GOROOT:-/usr/local/go}
GOPATH=${GOPATH:-/usr/local/go/go}
CNI_BIN_DIR=${CNI_BIN_DIR:-/opt/cni/bin/}
CNI_CONF_DIR=${CNI_CONF_DIR:-/etc/cni/net.d/}
ALLOW_PRIVILEGED=${ALLOW_PRIVILEGED:-true}
NET_PLUGIN=${NET_PLUGIN:-cni}

KUBE_ENABLE_CLUSTER_DNS=${KUBE_ENABLE_CLUSTER_DNS:-false}
export KUBECONFIG=${KUBECONFIG:-/var/run/kubernetes/admin.kubeconfig}

#TODO add autodiscovering
MACVLAN_INTERFACE=${MACVLAN_INTERFACE:-eno1}
SRIOV_INTERFACE=${SRIOV_INTERFACE:-enp3s0f0}

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
    echo "Download $MULTUS_CNI_REPO"
    git clone $MULTUS_CNI_REPO $WORKSPACE/multus-cni
    cd $WORKSPACE/multus-cni
    git checkout $MULTUS_CNI_BRANCH
    cd -

    echo "Download $SRIOV_CNI_REPO"
    git clone $SRIOV_CNI_REPO $WORKSPACE/sriov-cni 
    pushd $WORKSPACE/sriov-cni
    git checkout $SRIOV_CNI_BRANCH
    popd

    echo "Download $PLUGINS_REPO"
    git clone $PLUGINS_REPO $WORKSPACE/plugins
    pushd $WORKSPACE/plugins
    git checkout $PLUGINS_BRANCH
    ./build_linux.sh
    popd

    echo "Download $SRIOV_NETWORK_DEVICE_PLUGIN_REPO"
    git clone $SRIOV_NETWORK_DEVICE_PLUGIN_REPO $WORKSPACE/sriov-network-device-plugin
    pushd $WORKSPACE/sriov-network-device-plugin
    git checkout $SRIOV_NETWORK_DEVICE_PLUGIN_BRANCH
    make build
    popd
    kubectl delete -f $WORKSPACE/sriov-network-device-plugin/deployments/sriov-crd.yaml
    kubectl create -f $WORKSPACE/sriov-network-device-plugin/deployments/sriov-crd.yaml
    sudo mkdir -p /etc/pcidp/
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
    echo "Stop previous run of sriovdp"
    sudo kill $(pgrep sriovdp)
    nohup $WORKSPACE/sriov-network-device-plugin/build/sriovdp -logtostderr 10 2>&1|tee > $LOGDIR/sriovdp.log &
    return $? 
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
        limits:
          intel.com/sriov: 1
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
        pod_status=$(kubectl get pods | grep mofed-test-pod-1 |awk  '{print $3}')
        sleep 2
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

#TODO add check prereqs
#TODO add docker image mellanox/mlnx_ofed_linux-4.4-1.0.0.0-centos7.4 presence
clear_vfs
download_cni
configure_multus $MACVLAN_INTERFACE
pod_create
test_pod
echo "All logs $LOGDIR"
echo "All confs $ARTIFACTS"
exit $?
