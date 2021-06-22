#!/bin/bash -x

source ./common/common_functions.sh

export RECLONE=${RECLONE:-true}
export WORKSPACE=${WORKSPACE:-/tmp/k8s_$$}
export LOGDIR=$WORKSPACE/logs
export ARTIFACTS=$WORKSPACE/artifacts
export TIMEOUT=${TIMEOUT:-300}
export POLL_INTERVAL=${POLL_INTERVAL:-10}

export RDMA_CNI_REPO=${RDMA_CNI_REPO:-https://github.com/Mellanox/rdma-cni}
export RDMA_CNI_BRANCH=${RDMA_CNI_BRANCH:-''}
export RDMA_CNI_PR=${RDMA_CNI_PR:-''}
export RDMA_CNI_HARBOR_IMAGE=${RDMA_CNI_HARBOR_IMAGE:-${HARBOR_REGESTRY}/${HARBOR_PROJECT}/rdma-cni}

export SRIOV_CNI_REPO=${SRIOV_CNI_REPO:-https://github.com/k8snetworkplumbingwg/sriov-cni}
export SRIOV_CNI_BRANCH=${SRIOV_CNI_BRANCH:-''}
export SRIOV_CNI_PR=${SRIOV_CNI_PR:-''}

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

    build_github_project "rdma-cni" "TAG=$RDMA_CNI_HARBOR_IMAGE make image"
    let status=status+$?
    if [ "$status" != 0 ]; then
        echo "ERROR: Failed to build the rdma-cni project!"
        return $status
    fi
    change_image_name $RDMA_CNI_HARBOR_IMAGE mellanox/rdma-cni:latest

    cat > $ARTIFACTS/rdma-crd.yaml <<EOF
apiVersion: "k8s.cni.cncf.io/v1"
kind: NetworkAttachmentDefinition
metadata:
  name: sriov-rdma-net
  annotations:
    k8s.v1.cni.cncf.io/resourceName: mellanox.com/sriov_rdma
spec:
  config: '{
             "cniVersion": "0.3.1",
             "name": "sriov-rdma-net",
             "plugins": [{
                          "type": "sriov",
                          "link_state": "enable",
                          "ipam": {
                            "type": "host-local",
                            "subnet": "10.56.217.0/24",
                            "routes": [{
                              "dst": "0.0.0.0/0"
                            }],
                            "gateway": "10.56.217.1"
                          }
                        }, {
                          "type": "rdma"
                        }]
           }'
EOF

    echo "Download $SRIOV_CNI_REPO"
    sudo rm -rf $WORKSPACE/sriov-cni
    git clone ${SRIOV_CNI_REPO} $WORKSPACE/sriov-cni
    pushd $WORKSPACE/sriov-cni
    if test ${SRIOV_CNI_PR}; then
        git fetch --tags --progress ${SRIOV_CNI_REPO} +refs/pull/*:refs/remotes/origin/pr/*
        git pull origin pull/${SRIOV_CNI_PR}/head
    elif test ${SRIOV_CNI_BRANCH}; then
        git checkout ${SRIOV_CNI_BRANCH}
    fi
    git log -p -1 > $ARTIFACTS/sriov-cni-git.txt
    make build
    let status=status+$?
    if [ "$status" != 0 ]; then
        echo "Failed to build ${SRIOV_CNI_REPO} ${SRIOV_CNI_BRANCH}"
        return $status
    fi

    \cp build/* $CNI_BIN_DIR/
    popd

    deploy_sriov_device_plugin
    let status=status+$?
    if [ "$status" != 0 ]; then
        echo "ERROR: Failed to build the sriov-network-device-plugin project!"
        return $status
    fi

    cp /etc/pcidp/config.json $ARTIFACTS
    return 0
}


function create_vfs {
    if [ $SRIOV_INTERFACE == 'auto_detect' ]; then
        export SRIOV_INTERFACE=$(ls -l /sys/class/net/ | grep $(lspci |grep Mellanox | grep MT27800|head -n1|awk '{print $1}') | awk '{print $9}')
    fi

    sudo create_vfs.sh -i "$SRIOV_INTERFACE" -v "$VFS_NUM" --set-vfs-macs

}

#TODO add docker image mellanox/mlnx_ofed_linux-4.4-1.0.0.0-centos7.4 presence

[ -d $CNI_CONF_DIR ] && rm -rf $CNI_CONF_DIR && mkdir -p $CNI_CONF_DIR
[ -d $CNI_BIN_DIR ] && rm -rf $CNI_BIN_DIR && mkdir -p $CNI_BIN_DIR

create_workspace

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
    echo "Failed to deploy k8s!"
    exit 1
fi

download_and_build
if [ $? -ne 0 ]; then
    echo "Failed to download and build components"
    exit 1
fi

kubectl create -f $ARTIFACTS/rdma-crd.yaml

kubectl create -f $ARTIFACTS/configMap.yaml

kubectl create -f $WORKSPACE/sriov-network-device-plugin/deployments/k8s-v1.16/sriovdp-daemonset.yaml

kubectl create -f $WORKSPACE/rdma-cni/deployment/rdma-cni-daemonset.yaml

cp $WORKSPACE/sriov-network-device-plugin/deployments/k8s-v1.16/sriovdp-daemonset.yaml $ARTIFACTS/
screen -S multus_sriovdp -d -m  $WORKSPACE/sriov-network-device-plugin/build/sriovdp -logtostderr 10 2>&1|tee > $LOGDIR/sriovdp.log
echo "All code in $WORKSPACE"
echo "All logs $LOGDIR"
echo "All confs $ARTIFACTS"

echo "Setup is up and running. Run following to start tests:"
echo "# WORKSPACE=$WORKSPACE NETWORK=$NETWORK ./sriov/sriov_ci_test.sh"
popd
exit $status
