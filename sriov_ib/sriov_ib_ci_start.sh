#!/bin/bash
set -x

source ./common/common_functions.sh

export RECLONE=${RECLONE:-true}
export WORKSPACE=${WORKSPACE:-/tmp/k8s_$$}
export LOGDIR=$WORKSPACE/logs
export ARTIFACTS=$WORKSPACE/artifacts
export TIMEOUT=${TIMEOUT:-300}
export POLL_INTERVAL=${POLL_INTERVAL:-10}

export IB_K8S_REPO=${IB_K8S_REPO:-https://github.com/Mellanox/ib-kubernetes}
export IB_K8S_BRANCH=${IB_K8S_BRANCH:-''}
export IB_K8S_PR=${IB_K8S_PR:-''}
export IB_K8S_HARBOR_IMAGE=${IB_K8S_HARBOR_IMAGE:-${HARBOR_REGESTRY}/${HARBOR_PROJECT}/ib-kubernetes}

export SRIOV_IB_CNI_REPO=${SRIOV_IB_CNI_REPO:-https://github.com/mellanox/ib-sriov-cni}
export SRIOV_IB_CNI_BRANCH=${SRIOV_IB_CNI_BRANCH:-''}
export SRIOV_IB_CNI_PR=${SRIOV_IB_CNI_PR:-''}
export SRIOV_IB_CNI_HARBOR_IMAGE=${SRIOV_IB_CNI_HARBOR_IMAGE:-${HARBOR_REGESTRY}/${HARBOR_PROJECT}/ib-sriov-cni}

export GOPATH=${WORKSPACE}
export PATH=/usr/local/go/bin/:$GOPATH/src/k8s.io/kubernetes/third_party/etcd:$PATH

export CNI_BIN_DIR=${CNI_BIN_DIR:-/opt/cni/bin/}
export CNI_CONF_DIR=${CNI_CONF_DIR:-/etc/cni/net.d/}

export KUBECONFIG=${KUBECONFIG:-/etc/kubernetes/admin.conf}

# generate random network
N=$((1 + RANDOM % 128))
export NETWORK=${NETWORK:-"192.168.$N"}

#TODO add autodiscovering
export MACVLAN_INTERFACE=${MACVLAN_INTERFACE:-eno1}
export SRIOV_INTERFACE=${SRIOV_INTERFACE:-auto_detect}
export VFS_NUM=${VFS_NUM:-4}

function download_and_build {
    status=0
    if [ "$RECLONE" != true ] ; then
        return $status
    fi

    [ -d /var/lib/cni/sriov ] && rm -rf /var/lib/cni/sriov/*

    build_github_project "ib-k8s" "TAG=$IB_K8S_HARBOR_IMAGE make image"
    sed -i 's/AEMON_SM_PLUGIN: \"ufm\"/AEMON_SM_PLUGIN: \"noop\"/' $WORKSPACE/ib-k8s/deployment/ib-kubernetes-configmap.yaml

    let status=status+$?
    if [ "$status" != 0 ]; then
        echo "ERROR: Failed to build the ib-kubernetes project!"
        return $status
    fi
    change_image_name $IB_K8S_HARBOR_IMAGE mellanox/ib-kubernetes

    cat > $WORKSPACE/ib-k8s/deployment/ib-sriov-crd.yaml <<EOF
apiVersion: "k8s.cni.cncf.io/v1"
kind: NetworkAttachmentDefinition
metadata:
  name: ib-sriov-crd
  annotations:
    k8s.v1.cni.cncf.io/resourceName: mellanox.com/sriov_rdma
spec:
  config: '{
  "cniVersion": "0.3.1",
  "name": "sriov-network",
  "plugins":[{"type": "ib-sriov",
  "pkey": "0x223F",
  "link_state": "enable",
  "rdmaIsolation": true,
  "ibKubernetesEnabled" : true, 
  "ipam": {
                "type": "host-local",
                "subnet": "10.56.217.0/24",
                "routes": [{"dst": "0.0.0.0/0"}],
                "gateway": "10.56.217.1"
  }
}]}'
EOF

    build_github_project "sriov-ib-cni" "make build && TAG=$SRIOV_IB_CNI_HARBOR_IMAGE make image"
    let status=status+$?
    if [ "$status" != 0 ]; then
        echo "ERROR: Failed to build the ib-sriov-cni project!"
        return $status
    fi

    change_image_name $SRIOV_IB_CNI_HARBOR_IMAGE mellanox/ib-sriov-cni:latest
    pushd $WORKSPACE/sriov-ib-cni
    \cp build/* $CNI_BIN_DIR/
    popd

    deploy_sriov_device_plugin
    let status=status+$?
    if [ "$status" != 0 ]; then
        echo "ERROR: Failed to build the sriov-network-device-plugin project!"
        return $status
    fi

    return 0
}


function create_vfs {
    if [ $SRIOV_INTERFACE == 'auto_detect' ]; then
        export SRIOV_INTERFACE=$(ls -l /sys/class/net/ | grep $(lspci |grep Mellanox | grep -Ev 'MT27500|MT27520'|head -n1|awk '{print $1}') | awk '{print $9}')
    fi
    echo $VFS_NUM > /sys/class/net/$SRIOV_INTERFACE/device/sriov_numvfs
}

function reload_modules {
    systemctl stop opensm
    /etc/init.d/openibd restart
    sleep 5
    systemctl start opensm
    sleep 2
    rdma system set netns exclusive
    sleep 4
}

#TODO add docker image mellanox/mlnx_ofed_linux-4.4-1.0.0.0-centos7.4 presence

#reload_modules

let status=status+$?
if [ "$status" != 0 ]; then
    echo "Failed to create VFs!"
    exit $status
fi


create_workspace 

get_arch

pushd $WORKSPACE

load_rdma_modules
let status=status+$?
if [ "$status" != 0 ]; then
    exit $status
fi

enable_rdma_mode "exclusive"
let status=status+$?
if [ "$status" != 0 ]; then
    exit $status
fi

create_vfs

deploy_k8s_with_multus
if [ $? -ne 0 ]; then
    echo "Failed to deploy k8s screen"
    exit 1
fi

download_and_build
if [ $? -ne 0 ]; then
    echo "Failed to download and build components"
    exit 1
fi

kubectl label node $(kubectl get nodes -o name | cut -d'/' -f 2) node-role.kubernetes.io/master=

kubectl create -f $WORKSPACE/ib-k8s/deployment/ib-kubernetes-configmap.yaml
kubectl create -f $WORKSPACE/ib-k8s/deployment/ib-sriov-crd.yaml

kubectl create -f $ARTIFACTS/configMap.yaml
kubectl create -f $WORKSPACE/ib-k8s/deployment/ib-kubernetes.yaml
kubectl create -f $WORKSPACE/sriov-network-device-plugin/deployments/k8s-v1.16/sriovdp-daemonset.yaml

cp $WORKSPACE/ib-k8s/deployment/ib-sriov-crd.yaml $WORKSPACE/sriov-network-device-plugin/deployments/k8s-v1.16/sriovdp-daemonset.yaml $ARTIFACTS/
screen -S multus_sriovdp -d -m  $WORKSPACE/sriov-network-device-plugin/build/sriovdp -logtostderr 10 2>&1|tee > $LOGDIR/sriovdp.log
echo "All code in $WORKSPACE"
echo "All logs $LOGDIR"
echo "All confs $ARTIFACTS"

echo "Setup is up and running. Run following to start tests:"
echo "# WORKSPACE=$WORKSPACE NETWORK=$NETWORK ./sriov_ib/sriov_ib_ci_test.sh"
popd
exit $status
