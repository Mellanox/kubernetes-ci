#!/bin/bash -x

source ./common/common_functions.sh

export RECLONE=${RECLONE:-true}
export WORKSPACE=${WORKSPACE:-/tmp/k8s_$$}
export LOGDIR=$WORKSPACE/logs
export ARTIFACTS=$WORKSPACE/artifacts
export TIMEOUT=${TIMEOUT:-300}
export POLL_INTERVAL=${POLL_INTERVAL:-10}

export GOPATH=${WORKSPACE}
export PATH=/usr/local/go/bin/:$GOPATH/src/k8s.io/kubernetes/third_party/etcd:$PATH

export CNI_BIN_DIR=${CNI_BIN_DIR:-/opt/cni/bin/}
export CNI_CONF_DIR=${CNI_CONF_DIR:-/etc/cni/net.d/}

export KUBECONFIG=${KUBECONFIG:-/etc/kubernetes/admin.conf}

export IPOIB_CNI_REPO=${IPOIB_CNI_REPO:-https://github.com/Mellanox/ipoib-cni.git}
export IPOIB_CNI_BRANCH=${IPOIB_CNI_BRANCH:-''}
export IPOIB_CNI_PR=${IPOIB_CNI_PR-''}
export IPOIB_CNI_HARBOR_IMAGE=${IPOIB_CNI_HARBOR_IMAGE:-${HARBOR_REGESTRY}/${HARBOR_PROJECT}/ipoib-cni}

export K8S_RDMA_SHARED_DEV_PLUGIN_REPO=${K8S_RDMA_SHARED_DEV_PLUGIN_REPO:-https://github.com/Mellanox/k8s-rdma-shared-dev-plugin.git}
export K8S_RDMA_SHARED_DEV_PLUGIN_BRANCH=${K8S_RDMA_SHARED_DEV_PLUGIN_BRANCH:-''}
export K8S_RDMA_SHARED_DEV_PLUGIN_PR=${K8S_RDMA_SHARED_DEV_PLUGIN_PR-''}
export K8S_RDMA_SHARED_DEV_PLUGIN_HARBOR_IMAGE=${K8S_RDMA_SHARED_DEV_PLUGIN_HARBOR_IMAGE:-${HARBOR_REGESTRY}/${HARBOR_PROJECT}/k8s-rdma-shared-device-plugin}

function download_and_build {
    status=0

    build_github_project "ipoib-cni" "TAG=$IPOIB_CNI_HARBOR_IMAGE make image"
    let status=status+$?
    if [ "$status" != 0 ]; then
        echo "ERROR: Failed to build the ipoib-cni project!"
        return $status
    fi

    change_image_name $IPOIB_CNI_HARBOR_IMAGE mellanox/ipoib-cni:latest

    build_github_project "k8s-rdma-shared-dev-plugin" "TAG=$K8S_RDMA_SHARED_DEV_PLUGIN_HARBOR_IMAGE make image"
    let status=status+$?
    if [ "$status" != 0 ]; then
        echo "ERROR: Failed to build the k8s-rdma-shared-dev-plugin project!"
        return $status
    fi

    change_image_name $K8S_RDMA_SHARED_DEV_PLUGIN_HARBOR_IMAGE mellanox/k8s-rdma-shared-dev-plugin:latest
}

create_workspace

cp ./ipoib/yaml/k8s-rdma-shared-device-plugin-configmap.yaml ${ARTIFACTS}/

pushd $WORKSPACE

load_rdma_modules
let status=status+$?
if [ "$status" != 0 ]; then
    exit $status
fi

enable_rdma_mode "shared"
let status=status+$?
if [ "$status" != 0 ]; then
    exit $status
fi

deploy_k8s_with_multus
if [ $? -ne 0 ]; then
    echo "Failed to deploy k8s screen"
    exit 1
fi

download_and_build

/usr/local/bin/kubectl create -f ${ARTIFACTS}/k8s-rdma-shared-device-plugin-configmap.yaml
/usr/local/bin/kubectl create -f $WORKSPACE/k8s-rdma-shared-dev-plugin/images/k8s-rdma-shared-dev-plugin-ds.yaml
/usr/local/bin/kubectl create -f $WORKSPACE/ipoib-cni/images/ipoib-cni-daemonset.yaml
cat  > $ARTIFACTS/pod.yaml <<EOF
apiVersion: "k8s.cni.cncf.io/v1"
kind: NetworkAttachmentDefinition
metadata:
  name: ipoib-network
  annotations:
    k8s.v1.cni.cncf.io/resourceName: rdma/hca_shared_devices_a
spec:
  config: '{
  "cniVersion": "0.3.1",
  "type": "ipoib",
  "name": "mynet",
  "master": "ib0",
  "ipam": {
    "type": "host-local",
    "subnet": "10.56.217.0/24",
    "routes": [{
      "dst": "0.0.0.0/0"
    }],
      "gateway": "10.56.217.1"
  }
}'
EOF
/usr/local/bin/kubectl create -f $ARTIFACTS/pod.yaml
status=$?

echo "All code in $WORKSPACE"
echo "All logs $LOGDIR"
echo "All confs $ARTIFACTS"

echo "Setup is up and running. Run following to start tests:"
echo "# export KUBECONFIG=${KUBECONFIG}"
echo "# WORKSPACE=$WORKSPACE NETWORK=$NETWORK ./ipoib_cni_test.sh"

popd
exit $status
