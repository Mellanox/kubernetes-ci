#!/bin/bash -x

export RECLONE=${RECLONE:-true}
export WORKSPACE=${WORKSPACE:-/tmp/k8s_$$}
export LOGDIR=$WORKSPACE/logs
export ARTIFACTS=$WORKSPACE/artifacts
export TIMEOUT=${TIMEOUT:-300}
export POLL_INTERVAL=${POLL_INTERVAL:-10}

export ANTREA_CNI_REPO=${ANTREA_CNI_REPO:-https://github.com/vmware-tanzu/antrea.git}
export ANTREA_CNI_BRANCH=${ANTREA_CNI_BRANCH:-master}
export ANTREA_CNI_PR=${ANTREA_CNI_PR:-'786'}

export SRIOV_NETWORK_DEVICE_PLUGIN_REPO=${SRIOV_NETWORK_DEVICE_PLUGIN_REPO:-https://github.com/intel/sriov-network-device-plugin}
export SRIOV_NETWORK_DEVICE_PLUGIN_BRANCH=${SRIOV_NETWORK_DEVICE_PLUGIN_BRANCH:-master}
export SRIOV_NETWORK_DEVICE_PLUGIN_PR=${SRIOV_NETWORK_DEVICE_PLUGIN_PR-''}

export GOPATH=${WORKSPACE}
export PATH=/usr/local/go/bin/:$GOPATH/src/k8s.io/kubernetes/third_party/etcd:$PATH

export CNI_BIN_DIR=${CNI_BIN_DIR:-/opt/cni/bin/}
export CNI_CONF_DIR=${CNI_CONF_DIR:-/etc/cni/net.d/}
export KUBECONFIG=${KUBECONFIG:-/var/run/kubernetes/admin.kubeconfig}

#TODO add autodiscovering
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

function download_and_build {
    status=0
    if [ "$RECLONE" != true ] ; then
        return $status
    fi

    [ -d /var/lib/cni/sriov ] && rm -rf /var/lib/cni/sriov/*

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
          "resourceName": "sriov_antrea",
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
    
    
    echo "Download Antrea components"
    #wget https://raw.githubusercontent.com/vmware-tanzu/antrea/master/build/yamls/antrea.yml -P $ARTIFACTS/
    rm -rf $WORKSPACE/antrea
    git clone ${ANTREA_CNI_REPO} $WORKSPACE/antrea
    pushd $WORKSPACE/antrea
    if test ${ANTREA_CNI_PR}; then
        git fetch --tags --progress ${ANTREA_CNI_REPO} +refs/pull/*:refs/remotes/origin/pr/*
        git checkout origin/pr/${ANTREA_CNI_PR}/head
    elif test ${ANTREA_CNI_BRANCH}; then
        git checkout ${ANTREA_CNI_BRANCH}
    fi
    make build
    if [[ -z "$(grep hw-offload $WORKSPACE/antrea/build/yamls/antrea.yml)" ]];then
        sed -i '/start_ovs/a\        - --hw-offload' $WORKSPACE/antrea/build/yamls/antrea.yml
    fi
    git log -p -1 > $ARTIFACTS/antrea-git.txt
    
    cat > $ARTIFACTS/antrea-crd.yaml <<EOF
apiVersion: "k8s.cni.cncf.io/v1"
kind: NetworkAttachmentDefinition
metadata:
    name: sriov-antrea-net
    namespace: kube-system
    annotations:
        k8s.v1.cni.cncf.io/resourceName: mellanox.com/sriov_antrea
spec:
    config: '{
    "cniVersion": "0.3.1",
    "name": "sriov-antrea-net",
    "type": "antrea",
         "ipam": {
         "type": "host-local"
       }
}'
EOF
    popd
    return 0
}


function create_vfs {
    if [ $SRIOV_INTERFACE == 'auto_detect' ]; then
        export SRIOV_INTERFACE=$(ls -l /sys/class/net/ | grep $(lspci |grep Mellanox | grep MT27800|head -n1|awk '{print $1}') | awk '{print $9}')
    fi
    echo 0 > /sys/class/net/$SRIOV_INTERFACE/device/sriov_numvfs
    sleep 5
    echo $VFS_NUM > /sys/class/net/$SRIOV_INTERFACE/device/sriov_numvfs
    sleep 5

    vfs_pci_list=$(grep PCI_SLOT_NAME /sys/class/net/"$SRIOV_INTERFACE"/device/virtfn*/uevent | cut -d'=' -f2)
    for pci in $vfs_pci_list
    do
        echo "$pci" > /sys/bus/pci/drivers/mlx5_core/unbind
    done

   interface_pci=$(grep PCI_SLOT_NAME /sys/class/net/"$SRIOV_INTERFACE"/device/uevent\
                     | cut -d'=' -f2 -s)
   devlink dev eswitch set pci/"$interface_pci" mode switchdev

   for pci in $vfs_pci_list
   do
       echo "$pci" > /sys/bus/pci/drivers/mlx5_core/bind
   done
}
#TODO add docker image mellanox/mlnx_ofed_linux-4.4-1.0.0.0-centos7.4 presence


if [[ -f ./environment_common.sh ]]; then
    sudo ./environment_common.sh -m "exclusive"
    let status=status+$?
    if [ "$status" != 0 ]; then
        exit $status
    fi
else
    echo "no environment_common.sh file found in this directory make sure you run the script from the repo dir!"
    exit 1
fi

create_vfs

if [[ -f ./k8s_common.sh ]]; then
    sudo WORKSPACE=$WORKSPACE ./k8s_common.sh
    let status=status+$?
    if [ "$status" != 0 ]; then
        exit $status
    fi
else
    echo "no k8s_common.sh file found in this directory make sure you run the script from the repo dir!"
    exit 1
fi

pushd $WORKSPACE

download_and_build
if [ $? -ne 0 ]; then
    echo "Failed to download and build components"
    exit 1
fi
kubectl patch node "$(kubectl get nodes -o name | head -n 1 | cut -d / -f 2)" -p '{"spec":{"podCIDR":"192.169.50.0/24"}}' 

pushd $WORKSPACE/multus-cni 
./build
cp bin/multus /opt/cni/bin/
popd

echo " {\"cniVersion\": \"0.4.0\", \"name\": \"multus-cni-network\", \"type\": \"multus\", \"logLevel\": \"debug\", \"logFile\": \"/var/log/multus.log\", \"kubeconfig\": \"$KUBECONFIG\", \"clusterNetwork\": \"sriov-antrea-net\" }"\
       	> /etc/cni/net.d/00-multus.conf

kubectl create -f $ARTIFACTS/antrea-crd.yaml

kubectl create -f $ARTIFACTS/configMap.yaml
kubectl create -f $(ls -l $WORKSPACE/sriov-network-device-plugin/deployments/*/sriovdp-daemonset.yaml|tail -n1|awk '{print $NF}')


kubectl create -f $WORKSPACE/antrea/build/yamls/antrea.yml

cp $ARTIFACTS/antrea-crd.yaml $(ls -l $WORKSPACE/sriov-network-device-plugin/deployments/*/sriovdp-daemonset.yaml|tail -n1|awk '{print $NF}') $ARTIFACTS/
screen -S multus_sriovdp -d -m  $WORKSPACE/sriov-network-device-plugin/build/sriovdp -logtostderr 10 2>&1|tee > $LOGDIR/sriovdp.log
echo "All code in $WORKSPACE"
echo "All logs $LOGDIR"
echo "All confs $ARTIFACTS"

echo "Setup is up and running. Run following to start tests:"
echo "# WORKSPACE=$WORKSPACE NETWORK=$NETWORK ./sriov_antrea_test.sh"
popd
exit $status
