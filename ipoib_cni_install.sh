#!/bin/bash -x

export WORKSPACE=${WORKSPACE:-/tmp/k8s_$$}
export LOGDIR=$WORKSPACE/logs
export ARTIFACTS=$WORKSPACE/artifacts
export TIMEOUT=${TIMEOUT:-300}
export POLL_INTERVAL=${POLL_INTERVAL:-10}

export GOPATH=${WORKSPACE}
export PATH=/usr/local/go/bin/:$GOPATH/src/k8s.io/kubernetes/third_party/etcd:$PATH

export CNI_BIN_DIR=${CNI_BIN_DIR:-/opt/cni/bin/}
export CNI_CONF_DIR=${CNI_CONF_DIR:-/etc/cni/net.d/}

export KUBECONFIG=${KUBECONFIG:-/var/run/kubernetes/admin.kubeconfig}

export IPOIB_CNI_BRANCH=${IPOIB_CNI_BRANCH:-master}
export K8S_RDMA_SHARED_DEV_PLUGIN=${K8S_RDMA_SHARED_DEV_PLUGIN:-master}

echo "Working in $WORKSPACE"
mkdir -p $WORKSPACE
mkdir -p $LOGDIR
mkdir -p $ARTIFACTS


if [[ -f ./environment_common.sh ]]; then
    sudo ./environment_common.sh -m "shared"
    let status=status+$?
    if [ "$status" != 0 ]; then
        exit $status
    fi
else
    echo "no k8s_common.sh file found in this directory make sure you run the script from the repo dir!!!"
    exit 1
fi

if [[ -f ./k8s_common.sh ]]; then
    sudo ./k8s_common.sh
    let status=status+$?
    if [ "$status" != 0 ]; then
        exit $status
    fi
else
    echo "no k8s_common.sh file found in this directory make sure you run the script from the repo dir!!!"
    exit 1
fi

pushd $WORKSPACE

curl https://raw.githubusercontent.com/Mellanox/k8s-rdma-shared-dev-plugin/${K8S_RDMA_SHARED_DEV_PLUGIN}/images/k8s-rdma-shared-dev-plugin-config-map.yaml -o $ARTIFACTS/k8s-rdma-shared-dev-plugin-config-map.yaml
/usr/local/bin/kubectl create -f $ARTIFACTS/k8s-rdma-shared-dev-plugin-config-map.yaml
curl https://raw.githubusercontent.com/Mellanox/k8s-rdma-shared-dev-plugin/${K8S_RDMA_SHARED_DEV_PLUGIN}/images/k8s-rdma-shared-dev-plugin-ds.yaml -o $ARTIFACTS/k8s-rdma-shared-dev-plugin-ds.yaml
/usr/local/bin/kubectl create -f $ARTIFACTS/k8s-rdma-shared-dev-plugin-ds.yaml
curl https://raw.githubusercontent.com/Mellanox/ipoib-cni/${IPOIB_CNI_BRANCH}/images/ipoib-cni-daemonset.yaml -o $ARTIFACTS/ipoib-cni-daemonset.yaml
/usr/local/bin/kubectl create -f $ARTIFACTS/ipoib-cni-daemonset.yaml
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
