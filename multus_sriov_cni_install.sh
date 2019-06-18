#!/bin/bash

export RECLONE=${RECLONE:-true}
export WORKSPACE_K8S=${WORKSPACE_K8S:-/tmp/k8s_$$}
export LOGDIR=$WORKSPACE_K8S/logs
export ARTIFACTS=$WORKSPACE_K8S/artifacts
export TIMEOUT=300

export MULTUS_CNI_BRANCH=${MULTUS_CNI_BRANCH:-master}
export MULTUS_CNI_REPO=${MULTUS_CNI_REPO:-https://github.com/intel/multus-cni}

export SRIOV_CNI_BRANCH=${SRIOV_CNI_BRANCH:-master}
export SRIOV_CNI_REPO=${SRIOV_CNI_REPO:-https://github.com/intel/sriov-cni}

export PLUGINS_BRANCH=${PLUGINS_BRANCH:-master}
export PLUGINS_REPO=${PLUGINS_REPO:-https://github.com/containernetworking/plugins.git}

export SRIOV_NETWORK_DEVICE_PLUGIN_REPO=${SRIOV_NETWORK_DEVICE_PLUGIN_REPO:-https://github.com/intel/sriov-network-device-plugin}
export SRIOV_NETWORK_DEVICE_PLUGIN_BRANCH=${SRIOV_NETWORK_DEVICE_PLUGIN_BRANCH:-master}

export GOPATH=${WORKSPACE_K8S}
export PATH=/usr/local/go/bin/:$GOPATH/src/k8s.io/kubernetes/third_party/etcd:$PATH

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
export VFS_NUM=${VFS_NUM:-4}

echo "Working in $WORKSPACE_K8S"
mkdir -p $WORKSPACE_K8S
mkdir -p $LOGDIR
mkdir -p $ARTIFACTS

[ -d $CNI_CONF_DIR ] && rm -rf $CNI_CONF_DIR && mkdir -p $CNI_CONF_DIR
[ -d $CNI_BIN_DIR ] && rm -rf $CNI_BIN_DIR && mkdir -p $CNI_BIN_DIR

cd $WORKSPACE_K8S


function configure_multus {
    echo "Configure Multus"
    kubectl create -f $WORKSPACE_K8S/multus-cni/images/multus-daemonset.yml

    kubectl -n kube-system get ds
    rc=$?
    let stop=$(date '+%s')+$TIMEOUT
    d=$(date '+%s')
    while [ $d -lt $stop ]; do
       echo "Wait until multus is ready"
       ready=$(kubectl -n kube-system get ds |grep kube-multus-ds-amd64|awk '{print $4}')
       rc=$?
       kubectl -n kube-system get ds
       d=$(date '+%s')
       sleep 5
       if [ $ready -eq 1 ]; then
           echo "System is ready"
           break
      fi
    done
    if [ $d -gt $stop ]; then
        kubectl -n kube-system get ds
        echo "kube-multus-ds-amd64 is not ready in $TIMEOUT sec"
        exit 1
    fi

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
            "master": "$MACVLAN_INTERFACE",
            "mode": "bridge",
            "ipam": {
                "type": "host-local",
                "subnet": "192.168.1.0/24",
                "rangeStart": "192.168.1.100",
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
    git clone $MULTUS_CNI_REPO $WORKSPACE_K8S/multus-cni
    cd $WORKSPACE_K8S/multus-cni
    git checkout $MULTUS_CNI_BRANCH
    git log -p -1 > $ARTIFACTS/multus-cni.txt
    cd -

    echo "Download $SRIOV_CNI_REPO"
    git clone $SRIOV_CNI_REPO $WORKSPACE_K8S/sriov-cni
    pushd $WORKSPACE_K8S/sriov-cni
    git checkout $SRIOV_CNI_BRANCH
    git log -p -1 > $ARTIFACTS/sriov-cni.txt
    popd

    echo "Download $PLUGINS_REPO"
    git clone $PLUGINS_REPO $WORKSPACE_K8S/plugins
    pushd $WORKSPACE_K8S/plugins
    git checkout $PLUGINS_BRANCH
    git log -p -1 > $ARTIFACTS/plugins.txt
    bash ./build_linux.sh
    cp $WORKSPACE_K8S/plugins/bin/* $CNI_BIN_DIR/
    popd

    echo "Download $SRIOV_NETWORK_DEVICE_PLUGIN_REPO"
    git clone $SRIOV_NETWORK_DEVICE_PLUGIN_REPO $WORKSPACE_K8S/sriov-network-device-plugin
    pushd $WORKSPACE_K8S/sriov-network-device-plugin
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


function create_vfs {
    echo 0 > /sys/class/net/$SRIOV_INTERFACE/device/sriov_numvfs
    echo $VFS_NUM > /sys/class/net/$SRIOV_INTERFACE/device/sriov_numvfs
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
    kill -9 $(ps -ef |grep etcd|grep http|awk '{print $2}')
    $GOPATH/src/k8s.io/kubernetes/hack/install-etcd.sh
    $GOPATH/src/k8s.io/kubernetes/hack/local-up-cluster.sh 2>&1|tee > $LOGDIR/kubernetes.log &
    kubectl get pods
    rc=$?
    let stop=$(date '+%s')+$TIMEOUT
    d=$(date '+%s')
    while [ $d -lt $stop ]; do
       echo "Wait until K8S is up"
       kubectl get pods
       rc=$?
       d=$(date '+%s')
       sleep 5
       echo "rc=$?"
       if [ $rc -eq 0 ]; then
           echo "K8S is up and running"
           return 0
      fi
    done
    echo "K8S failed to run in $TIMEOUT sec"
    exit 1
}


#TODO add docker image mellanox/mlnx_ofed_linux-4.4-1.0.0.0-centos7.4 presence

create_vfs
download_cni

install_k8s
configure_multus

kubectl create -f $WORKSPACE_K8S/sriov-network-device-plugin/deployments/sriov-crd.yaml
kubectl create -f $WORKSPACE_K8S/sriov-cni/images/sriov-cni-daemonset.yaml

kill $(pgrep sriovdp)
$WORKSPACE_K8S/sriov-network-device-plugin/build/sriovdp -logtostderr 10 2>&1|tee > $LOGDIR/sriovdp.log &
status=$?
echo "All code in $WORKSPACE_K8S"
echo "All logs $LOGDIR"
echo "All confs $ARTIFACTS"

echo "Setup is up and running. Run following to start tests:"
echo "# WORKSPACE_K8S=$WORKSPACE_K8S ./multus_sriov_cni_test.sh"
exit $status
