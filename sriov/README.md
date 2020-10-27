# SRIOV project
The SRIOV project is used to deploy Kubernetes on a Mellanox ethernet card (ConnectX cards configured to be ethernet), and configure the network to use two networks: the first is the macvlan as the primary network, the second is SRIOV based network for workloads.

### Components
The SRIOV project builds and deploy the following components:
 
* [Kubernetes](https://github.com/kubernetes/kubernetes).
* [Multus](https://github.com/intel/multus-cni).
* [Container networking plugins](https://github.com/containernetworking/plugins.git).
* [Mellanox RDMA cni](https://github.com/Mellanox/rdma-cni).
* [SRIOV network device plugin](https://github.com/k8snetworkplumbingwg/sriov-network-device-plugin).
* [SRIOV cni](https://github.com/k8snetworkplumbingwg/sriov-cni). 

### Configurations
In addition to the common configurations found at [README.md](./README.md), the sriov project uses the following configurations:

|  Variable |  DEFAULT VALUE |  Comments |
|  ------ |  ------ |  ------ |
|  RDMA_CNI_REPO | https://github.com/Mellanox/rdma-cni | RDMA cni repo to use |
|  RDMA_CNI_BRANCH | master | RDMA cni branch to use |
|  RDMA_CNI_PR | | RDMA cni pull request to pull, adding this will ignore RDMA_CNI_BRANCH |
|  SRIOV_CNI_REPO | https://github.com/k8snetworkplumbingwg/sriov-cni | SRIOV cni repo to use |
|  SRIOV_CNI_BRANCH | master | SRIOV cni branch to use |
|  SRIOV_CNI_PR | '' | SRIOV cni pull request to pull,  adding this will ignore SRIOV_CNI_BRANCH |
|  SRIOV_NETWORK_DEVICE_PLUGIN_REPO | https://github.com/k8snetworkplumbingwg/sriov-network-device-plugin | SRIOV network device plugin repo to use |
|  SRIOV_NETWORK_DEVICE_PLUGIN_BRANCH | master | SRIOV network device plugin branch to build |
|  SRIOV_NETWORK_DEVICE_PLUGIN_PR-'' | SRIOV network device plugin pull request to pull, adding this will ignore SRIOV_NETWORK_DEVICE_PLUGIN_BRANCH |
|  MACVLAN_INTERFACE | eno1 | macvlan network master interface |
|  SRIOV_INTERFACE | auto_detect | SRIOV network device, if not specified, the first Mellanox card will be used (does not support ConnectX3) |
|  VFS_NUM | 4 | number of SRIOV VFs to create |
