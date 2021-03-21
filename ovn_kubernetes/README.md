# OVN_KUBERNETES project
Ovn-Kubernetes project is used to deploy Kubernetes on a Mellanox ethernet card (ConnectX cards configured to be ethernet), and configure the network to use SRIOV based network, and use the ovn-kubernetes project as the main CNI.

### Components
Ovn-Kubernetes project builds and deploy the following components:
 
* [Kubernetes](https://github.com/kubernetes/kubernetes).
* [Multus](https://github.com/intel/multus-cni).
* [SRIOV network device plugin](https://github.com/k8snetworkplumbingwg/sriov-network-device-plugin).
* [Ovn-Kubernetes](https://github.com/ovn-org/ovn-kubernetes.git). 

### Configurations
In addition to the common configurations found at [README.md](./README.md), the ovn-kubernetes project uses the following configurations:

|  Variable |  DEFAULT VALUE |  Comments |
|  ------ |  ------ |  ------ |
|  OVN_KUBERNETES_CNI_REPO | https://github.com/ovn-org/ovn-kubernetes.git | ovn-kubernetes project repo to use |
|  OVN_KUBERNETES_CNI_BRANCH | master | ovn-kubernetes project branch to use |
|  OVN_KUBERNETES_CNI_PR | | ovn-kubernetes project pull request to pull, adding this will ignore OVN_KUBERNETES_CNI_BRANCH |
|  SRIOV_NETWORK_DEVICE_PLUGIN_REPO | https://github.com/k8snetworkplumbingwg/sriov-network-device-plugin | SRIOV network device plugin repo to use |
|  SRIOV_NETWORK_DEVICE_PLUGIN_BRANCH | master | SRIOV network device plugin branch to build |
|  SRIOV_NETWORK_DEVICE_PLUGIN_PR-'' | SRIOV network device plugin pull request to pull, adding this will ignore SRIOV_NETWORK_DEVICE_PLUGIN_BRANCH |
|  SRIOV_INTERFACE | auto_detect | SRIOV network device, if not specified, the first Mellanox card will be used (does not support ConnectX3) |
|  VFS_NUM | 4 | number of SRIOV VFs to create |
