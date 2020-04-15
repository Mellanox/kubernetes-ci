#!/bin/bash -x

export RECLONE=${RECLONE:-true}
export WORKSPACE=${WORKSPACE:-/tmp/k8s_$$}
export LOGDIR=$WORKSPACE/logs
export ARTIFACTS=$WORKSPACE/artifacts
export TIMEOUT=${TIMEOUT:-300}
export POLL_INTERVAL=${POLL_INTERVAL:-10}

export RDMA_CNI_REPO=${RDMA_CNI_REPO:-https://github.com/Mellanox/rdma-cni}
export RDMA_CNI_BRANCH=${RDMA_CNI_BRANCH:-master}
export RDMA_CNI_PR=${RDMA_CNI_PR:-''}

export SRIOV_CNI_REPO=${SRIOV_CNI_REPO:-https://github.com/intel/sriov-cni}
export SRIOV_CNI_BRANCH=${SRIOV_CNI_BRANCH:-master}
export SRIOV_CNI_PR=${SRIOV_CNI_PR:-''}

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

echo "Get CPU architechture"
export ARCH="amd"
if [[ $(uname -a) == *"ppc"* ]]; then
   export ARCH="ppc"
fi

function load_rdma_modules {
    status=0
    if [ $SRIOV_INTERFACE == 'auto_detect' ]; then
        export SRIOV_INTERFACE=$(ls -l /sys/class/net/ | grep $(lspci |grep Mellanox | grep MT27800|head -n1|awk '{print $1}') | awk '{print $9}')
    fi
    echo 0 > /sys/class/net/$SRIOV_INTERFACE/device/sriov_numvfs
    sleep 5

    if [[ -n "$(lsmod | grep rdma_cm)" ]]; then
        modprobe -r rdma_cm
        if [ "$?" != "0" ]; then
            echo "Warning: Failed to remove rdma_cm module"
        fi
        sleep 2
    fi
    modprobe rdma_cm
    let status=status+$?
    if [ "$status" != 0 ]; then
        echo "Failed to load rdma_cm module"
        return $status
    fi

    if [[ -n "$(lsmod | grep rdma_ucm)" ]]; then
        modprobe -r rdma_ucm
        if [ "$?" != "0" ]; then
            echo "Warning: faild to remove the rdma_ucm module"
        fi
        sleep 2
    fi
    modprobe rdma_ucm
    let status=status+$?
    if [ "$status" != 0 ]; then
        echo "Failed to load rdma_ucm module"
        return $status
    fi

    return $status
}

function download_and_build {
    status=0
    if [ "$RECLONE" != true ] ; then
        return $status
    fi

    [ -d $CNI_CONF_DIR ] && rm -rf $CNI_CONF_DIR && mkdir -p $CNI_CONF_DIR
    [ -d $CNI_BIN_DIR ] && rm -rf $CNI_BIN_DIR && mkdir -p $CNI_BIN_DIR
    [ -d /var/lib/cni/sriov ] && rm -rf /var/lib/cni/sriov/*

    echo "Download $RDMA_CNI_REPO"
    rm -rf $WORKSPACE/rdma-cni
    git clone $RDMA_CNI_REPO $WORKSPACE/rdma-cni
    pushd $WORKSPACE/rdma-cni
    # Check if part of Pull Request and
    if test ${RDMA_CNI_PR}; then
        git fetch --tags --progress $RDMA_CNI_REPO +refs/pull/*:refs/remotes/origin/pr/*
        git pull origin pull/${RDMA_CNI_PR}/head
    elif test $RDMA_CNI_BRANCH; then
        git checkout $RDMA_CNI_BRANCH
    fi

    cat > deployment/rdma-crd.yaml <<EOF
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

    git log -p -1 > $ARTIFACTS/rdma-cni-git.txt
    make
    let status=status+$?
   
    if [ "$status" != 0 ]; then
        echo "Failed to build ${RDMA_CNI_REPO} ${RDMA_CNI_BRANCH}"
        return $status
    fi

    make image
    let status=status+$?
    if [ "$status" != 0 ]; then
        echo "Failed to create rdma cni images."
        return $status
    fi
    \cp build/* $CNI_BIN_DIR/
    popd

    echo "Download $SRIOV_CNI_REPO"
    rm -rf $WORKSPACE/sriov-cni
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
    make image
    let status=status+$?
    if [ "$status" != 0 ]; then
        echo "Failed to build ${SRIOV_CNI_REPO} ${SRIOV_CNI_BRANCH}"
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
          "resourceName": "sriov_rdma",
          "selectors": {
                  "vendors": ["15b3"],
                  "devices": ["1018"],
                  "drivers": ["mlx5_core"],
                  "isRdma": true
              }
      }
      ]
    }
EOF

    cp /etc/pcidp/config.json $ARTIFACTS
    return 0
}


function create_vfs {
    if [ $SRIOV_INTERFACE == 'auto_detect' ]; then
        export SRIOV_INTERFACE=$(ls -l /sys/class/net/ | grep $(lspci |grep Mellanox | grep MT27800|head -n1|awk '{print $1}') | awk '{print $9}')
    fi
    echo $VFS_NUM > /sys/class/net/$SRIOV_INTERFACE/device/sriov_numvfs
    let last_index=$VFS_NUM-1
    for i in `seq 0 $last_index`; do
        ip link set $SRIOV_INTERFACE vf $i mac 00:22:00:11:22:$(printf '%02x' $i)
        pci=`readlink /sys/class/net/$SRIOV_INTERFACE/device/virtfn$i | sed 's/..\///'`
	echo "$pci" > /sys/bus/pci/drivers/mlx5_core/unbind
	echo "$pci" > /sys/bus/pci/drivers/mlx5_core/bind
    done 
}
#TODO add docker image mellanox/mlnx_ofed_linux-4.4-1.0.0.0-centos7.4 presence

pushd $WORKSPACE

load_rdma_modules
if [ $? -ne 0 ]; then
    echo "Failed to load rdma modules"
    exit 1
fi

create_vfs

download_and_build
if [ $? -ne 0 ]; then
    echo "Failed to download and build components"
    exit 1
fi
popd

if [[ -f ./k8s_common.sh ]]; then
	sudo ./k8s_common.sh
else
	echo "no k8s_common.sh file found in this directory make sure you run the script from the repo dir!!!"
        popd
	exit 1
fi

pushd $WORKSPACE

kubectl create -f $WORKSPACE/rdma-cni/deployment/rdma-crd.yaml

kubectl create -f $ARTIFACTS/configMap.yaml
kubectl create -f $(ls -l $WORKSPACE/sriov-network-device-plugin/deployments/*/sriovdp-daemonset.yaml|tail -n1|awk '{print $NF}')

kubectl create -f $WORKSPACE/rdma-cni/deployment/rdma-cni-daemonset.yaml

cp $WORKSPACE/rdma-cni/deployment/rdma-crd.yaml $(ls -l $WORKSPACE/sriov-network-device-plugin/deployments/*/sriovdp-daemonset.yaml|tail -n1|awk '{print $NF}') $ARTIFACTS/
screen -S multus_sriovdp -d -m  $WORKSPACE/sriov-network-device-plugin/build/sriovdp -logtostderr 10 2>&1|tee > $LOGDIR/sriovdp.log
echo "All code in $WORKSPACE"
echo "All logs $LOGDIR"
echo "All confs $ARTIFACTS"

echo "Setup is up and running. Run following to start tests:"
echo "# WORKSPACE=$WORKSPACE NETWORK=$NETWORK ./sriov_cni_test.sh"
popd
exit $status
