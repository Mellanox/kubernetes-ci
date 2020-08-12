#!/bin/bash -x

export RECLONE=${RECLONE:-true}
export WORKSPACE=${WORKSPACE:-/tmp/k8s_$$}
export LOGDIR=$WORKSPACE/logs
export ARTIFACTS=$WORKSPACE/artifacts
export TIMEOUT=${TIMEOUT:-300}
export POLL_INTERVAL=${POLL_INTERVAL:-10}

export IB_K8S_REPO=${IB_K8S_REPO:-https://github.com/Mellanox/ib-kubernetes}
export IB_K8S_BRANCH=${IB_K8S_BRANCH:-master}
export IB_K8S_PR=${IB_K8S_PR:-''}

export SRIOV_IB_CNI_REPO=${SRIOV_IB_CNI_REPO:-https://github.com/mellanox/ib-sriov-cni}
export SRIOV_IB_CNI_BRANCH=${SRIOV_IB_CNI_BRANCH:-master}
export SRIOV_IB_CNI_PR=${SRIOV_IB_CNI_PR:-''}

export SRIOV_NETWORK_DEVICE_PLUGIN_REPO=${SRIOV_NETWORK_DEVICE_PLUGIN_REPO:-https://github.com/intel/sriov-network-device-plugin}
export SRIOV_NETWORK_DEVICE_PLUGIN_BRANCH=${SRIOV_NETWORK_DEVICE_PLUGIN_BRANCH:-master}
export SRIOV_NETWORK_DEVICE_PLUGIN_PR=${SRIOV_NETWORK_DEVICE_PLUGIN_PR-''}

export GOPATH=${WORKSPACE}
export PATH=/usr/local/go/bin/:$GOPATH/src/k8s.io/kubernetes/third_party/etcd:$PATH

export CNI_BIN_DIR=${CNI_BIN_DIR:-/opt/cni/bin/}
export CNI_CONF_DIR=${CNI_CONF_DIR:-/etc/cni/net.d/}

export KUBECONFIG=${KUBECONFIG:-/var/run/kubernetes/admin.kubeconfig}

# generate random network
N=$((1 + RANDOM % 128))
export NETWORK=${NETWORK:-"192.168.$N"}

#TODO add autodiscovering
export MACVLAN_INTERFACE=${MACVLAN_INTERFACE:-eno1}
export SRIOV_INTERFACE=${SRIOV_INTERFACE:-auto_detect}
export VFS_NUM=${VFS_NUM:-4}

echo "Working in $WORKSPACE"
mkdir -p $WORKSPACE
mkdir -p $LOGDIR
mkdir -p $ARTIFACTS

function download_and_build {
    status=0
    if [ "$RECLONE" != true ] ; then
        return $status
    fi

    [ -d /var/lib/cni/sriov ] && rm -rf /var/lib/cni/sriov/*

    echo "Download $IB_K8S_REPO"
    rm -rf $WORKSPACE/ib-kubernetes
    git clone $IB_K8S_REPO $WORKSPACE/ib-kubernetes
    pushd $WORKSPACE/ib-kubernetes
    # Check if part of Pull Request and
    if test ${IB_K8S_PR}; then
        git fetch --tags --progress $IB_K8S_REPO +refs/pull/*:refs/remotes/origin/pr/*
        git pull origin pull/${IB_K8S_PR}/head
    elif test $IB_K8S_BRANCH; then
        git checkout $IB_K8S_BRANCH
    fi

    cat > deployment/ib-sriov-crd.yaml <<EOF
apiVersion: "k8s.cni.cncf.io/v1"
kind: NetworkAttachmentDefinition
metadata:
  name: ib-sriov-crd
  annotations:
    k8s.v1.cni.cncf.io/resourceName: mellanox.com/mlnx_sriov_rdma_ib
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

    git log -p -1 > $ARTIFACTS/ib-kubernetes-git.txt

    sed -i 's/AEMON_SM_PLUGIN: "ufm"/AEMON_SM_PLUGIN: "noop"/' deployment/ib-kubernetes-configmap.yaml

    make image
    let status=status+$?
    if [ "$status" != 0 ]; then
        echo "Failed to create ib kubernetes images."
        return $status
    fi
    popd

    echo "Download $SRIOV_IB_CNI_REPO"
    rm -rf $WORKSPACE/ib-sriov-cni
    git clone ${SRIOV_IB_CNI_REPO} $WORKSPACE/ib-sriov-cni
    pushd $WORKSPACE/ib-sriov-cni
    if test ${SRIOV_IB_CNI_PR}; then
        git fetch --tags --progress ${SRIOV_IB_CNI_REPO} +refs/pull/*:refs/remotes/origin/pr/*
        git pull origin pull/${SRIOV_IB_CNI_PR}/head
    elif test ${SRIOV_IB_CNI_BRANCH}; then
        git checkout ${SRIOV_IB_CNI_BRANCH}
    fi
    git log -p -1 > $ARTIFACTS/sriov-cni-git.txt
    make build
    let status=status+$?
    if [ "$status" != 0 ]; then
        echo "Failed to build ${SRIOV_IB_CNI_REPO} ${SRIOV_IB_CNI_BRANCH}"
        return $status
    fi
    make image
    let status=status+$?
    if [ "$status" != 0 ]; then
        echo "Failed to build ${SRIOV_IB_CNI_REPO} ${SRIOV_IB_CNI_BRANCH}"
        return $status
    fi
    \cp build/* $CNI_BIN_DIR/
    popd

    echo "Download ${SRIOV_NETWORK_DEVICE_PLUGIN_REPO}"
    rm -rf $WORKSPACE/sriov-network-device-plugin
    git clone ${SRIOV_NETWORK_DEVICE_PLUGIN_REPO} $WORKSPACE/sriov-network-device-plugin
    pushd $WORKSPACE/sriov-network-device-plugin
    if test ${SRIOV_NETWORK_DEVICE_PLUGIN_PR}; then
        git fetch --tags --progress ${SRIOV_NETWORK_DEVICE_PLUGIN_REPO} +refs/pull/*:refs/remotes/origin/pr/*
        git pull origin pull/${SRIOV_NETWORK_DEVICE_PLUGIN_PR}/head
    elif test ${SRIOV_NETWORK_DEVICE_PLUGIN_BRANCH}; then
        git checkout ${SRIOV_NETWORK_DEVICE_PLUGIN_BRANCH}
    fi
    git log -p -1 > $ARTIFACTS/sriov-network-device-plugin-git.txt
    make build
    let status=status+$?
    make image
    let status=status+$?
    if [ "$status" != 0 ]; then
        echo "Failed to build ${SRIOV_NETWORK_DEVICE_PLUGIN_REPO} ${SRIOV_NETWORK_DEVICE_PLUGIN_BRANCH} ${SRIOV_NETWORK_DEVICE_PLUGIN_BRANCH}"
        return $status
    fi

    \cp build/* $CNI_BIN_DIR/
    popd
    cat > $ARTIFACTS/configMap.yaml <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: sriovdp-config
  namespace: kube-system
data:
  config.json: |
    {
      "resourceList": [{
          "resourcePrefix": "mellanox.com",
          "resourceName": "mlnx_sriov_rdma_ib",
          "selectors": {
                  "vendors": ["15b3"],
                  "devices": ["1018"],
                  "isRdma": true,
                  "drivers": ["mlx5_core"]
              }
      }
      ]
    }
EOF

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


if [[ -f ./common_functions.sh ]]; then
    source ./common_functions.sh
    let status=status+$?
    if [ "$status" != 0 ]; then
        echo "Failed to source common_functions.sh"
        exit $status
    fi
else
    echo "no common_functions.sh file found in this directory make sure you run the script from the repo dir!"
    exit 1
fi

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

kubectl create -f $WORKSPACE/ib-kubernetes/deployment/ib-kubernetes-configmap.yaml
kubectl create -f $WORKSPACE/ib-kubernetes/deployment/ib-sriov-crd.yaml

kubectl create -f $ARTIFACTS/configMap.yaml
kubectl create -f $WORKSPACE/ib-kubernetes/deployment/ib-kubernetes.yaml
kubectl create -f $(ls -l $WORKSPACE/sriov-network-device-plugin/deployments/*/sriovdp-daemonset.yaml|tail -n1|awk '{print $NF}')

cp $WORKSPACE/ib-kubernetes/deployment/ib-sriov-crd.yaml $(ls -l $WORKSPACE/sriov-network-device-plugin/deployments/*/sriovdp-daemonset.yaml|tail -n1|awk '{print $NF}') $ARTIFACTS/
screen -S multus_sriovdp -d -m  $WORKSPACE/sriov-network-device-plugin/build/sriovdp -logtostderr 10 2>&1|tee > $LOGDIR/sriovdp.log
echo "All code in $WORKSPACE"
echo "All logs $LOGDIR"
echo "All confs $ARTIFACTS"

echo "Setup is up and running. Run following to start tests:"
echo "# WORKSPACE=$WORKSPACE NETWORK=$NETWORK ./sriov_ib_cni_test.sh"
popd
exit $status
