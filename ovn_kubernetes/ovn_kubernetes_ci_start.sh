#!/bin/bash -x
source ./common/common_functions.sh

export RECLONE=${RECLONE:-true}
export WORKSPACE=${WORKSPACE:-/tmp/k8s_$$}
export LOGDIR=$WORKSPACE/logs
export ARTIFACTS=$WORKSPACE/artifacts
export TIMEOUT=${TIMEOUT:-300}
export POLL_INTERVAL=${POLL_INTERVAL:-10}

export OVN_KUBERNETES_CNI_REPO=${OVN_KUBERNETES_CNI_REPO:-https://github.com/ovn-org/ovn-kubernetes.git}
export OVN_KUBERNETES_CNI_BRANCH=${OVN_KUBERNETES_CNI_BRANCH:-''}
export OVN_KUBERNETES_CNI_PR=${OVN_KUBERNETES_CNI_PR:-''}
export OVN_KUBERNETES_CNI_HARBOR_IMAGE=${OVN_KUBERNETES_CNI_HARBOR_IMAGE:-${HARBOR_REGESTRY}/${HARBOR_PROJECT}/ovn-kubernetes}

export GOPATH=${WORKSPACE}
export PATH=/usr/local/go/bin/:$GOPATH/src/k8s.io/kubernetes/third_party/etcd:$PATH

export CNI_BIN_DIR=${CNI_BIN_DIR:-/opt/cni/bin/}
export CNI_CONF_DIR=${CNI_CONF_DIR:-/etc/cni/net.d/}
export KUBECONFIG=${KUBECONFIG:-/etc/kubernetes/admin.conf}

export SRIOV_INTERFACE=${SRIOV_INTERFACE:-auto_detect}
export VFS_NUM=${VFS_NUM:-4}

function download_and_build {
    status=0

    build_github_project "ovn-kubernetes-cni" "cd dist/images/ && make ubuntu"

    let status=status+$?
    if [ "$status" != 0 ]; then
        echo "ERROR: Failed to build the ovn-kubernetes project!"
        return $status
    fi
# TODO this is nightly (not supported yet)
    if [[ -z "${OVN_KUBERNETES_CNI_PR}${OVN_KUBERNETES_CNI_BRANCH}" ]];then
        change_image_name $OVN_KUBERNETES_CNI_HARBOR_IMAGE antrea/antrea-ubuntu
    fi
}


function create_vfs {
    if [ $SRIOV_INTERFACE == 'auto_detect' ]; then
        export SRIOV_INTERFACE=$(get_auto_net_device)
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

function deploy_ovn_kubernetes {
   pushd $WORKSPACE/ovn-kubernetes-cni/dist/images
   ./daemonset.sh --image=ovn-kube-u \
    --net-cidr=192.168.0.0/16/24 --svc-cidr=$SERVICE_CIDER \
    --gateway-mode="local" \
    --k8s-apiserver=https://$API_HOST_IP:6443

   modprobe ip6_tables

   # Configmap
   kubectl create -f ../yaml/ovn-setup.yaml
   # Ovs
   kubectl create -f ../yaml/ovs-node.yaml
   #OVN Database
   kubectl create -f ../yaml/ovnkube-db.yaml
   # ovnkube Master pod
   kubectl create -f ../yaml/ovnkube-master.yaml
   # ovnkube node for non smart nic nodes
   kubectl create -f ../yaml/ovnkube-node.yaml

   popd
}

create_workspace

create_vfs

pushd $WORKSPACE

deploy_k8s_with_multus_without_cni_plugins
if [ $? -ne 0 ]; then
    echo "Failed to deploy k8s"
    exit 1
fi


deploy_sriov_device_plugin
if [ $? -ne 0 ]; then
    echo "ERROR: Failed to build the sriov-network-device-plugin project!"
    exit 1
fi

pushd $WORKSPACE

download_and_build
if [ $? -ne 0 ]; then
    echo "Failed to download and build components"
    exit 1
fi

# Deploy sriov device plugin
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
          "resourceName": "ovn_kube",
          "selectors": {
                  "vendors": ["15b3"],
                  "devices": ["1018"],
                  "drivers": ["mlx5_core"]
              }
      }
      ]
    }
EOF
kubectl create -f $(ls -l $WORKSPACE/sriov-network-device-plugin/deployments/*/sriovdp-daemonset.yaml|tail -n1|awk '{print $NF}')

# Deploy ovn-kubernetes
deploy_ovn_kubernetes
wait_pod_state 'ovnkube-node' 'Running'
if [ $? -ne 0 ]; then
    echo "ovnkube-node failed to run"
    exit 1
fi

cat <<EOF | kubectl create -f -
apiVersion: "k8s.cni.cncf.io/v1"
kind: NetworkAttachmentDefinition
metadata:
  name: ovn-kube
  namespace: kube-system
  annotations:
    k8s.v1.cni.cncf.io/resourceName: mellanox.com/ovn_kube
spec:
  config: '{"cniVersion":"0.4.0","name":"ovn-kubernetes","type":"ovn-k8s-cni-overlay", "kubeconfig":"", "ipam":{},"dns":{}}'
EOF

echo "All code in $WORKSPACE"
echo "All logs $LOGDIR"
echo "All confs $ARTIFACTS"

echo "Setup is up and running. Run following to start tests:"
echo "# WORKSPACE=$WORKSPACE NETWORK=$NETWORK ./ovn_kubernetes_test.sh"
popd
exit $status
