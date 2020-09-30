# SRIOV IB project
The SRIOV IB project is used to deploy Kubernetes on a Mellanox Infiniband card (ConnectX cards configured to be Infiniband), and configure the network to use two networks: the first is the macvlan as the primary network, the second is SRIOV based network for workloads.

### Components
The SRIOV IB project builds and deploy the following components:
 
* [Kubernetes](https://github.com/kubernetes/kubernetes).
* [Multus](https://github.com/intel/multus-cni).
* [Container networking plugins](https://github.com/containernetworking/plugins.git).
* [Mellanox IB Kubernetes](https://github.com/Mellanox/ib-kubernetes).
* [SRIOV network device plugin](https://github.com/intel/sriov-network-device-plugin).
* [Mellanox IB SRIOV CNI](https://github.com/mellanox/ib-sriov-cni). 

### Configurations
In addition to the common configurations found at [README.md](./README.md), the sriov ib project uses the following configurations:

| Variable |  DEFAULT VALUE |  Comments |
| ------ |  ------ |  ------ |
| IB_K8S_REPO | https://github.com/Mellanox/ib-kubernetes | IB Kubernetes project repo to use |
| IB_K8S_BRANCH | master | IB Kubernetes project branch to build |
| IB_K8S_PR | '' | IB Kubernetes pull request to pull, adding this will ignore IB_K8S_BRANCH |
| SRIOV_IB_CNI_REPO | https://github.com/mellanox/ib-sriov-cni | IB SRIOV CNI repo to use |
| SRIOV_IB_CNI_BRANCH | master | IB SRIOV project branch to build |
| SRIOV_IB_CNI_PR | '' | IB SRIOV pull request to pull, adding this will ignore SRIOV_IB_CNI_BRANCH |
| SRIOV_NETWORK_DEVICE_PLUGIN_REPO | https://github.com/intel/sriov-network-device-plugin | SRIOV network device plugin repo to use |
| SRIOV_NETWORK_DEVICE_PLUGIN_BRANCH | master | SRIOV network device plugin branch to build |
| SRIOV_NETWORK_DEVICE_PLUGIN_PR-'' | SRIOV network device plugin pull request to pull, adding this will ignore SRIOV_NETWORK_DEVICE_PLUGIN_BRANCH |
| MACVLAN_INTERFACE | eno1 | macvlan network master interface |
| SRIOV_INTERFACE | auto_detect | SRIOV network device, if not specified, the first Mellanox card will be used (does not support ConnectX3) |
| VFS_NUM | 4 | number of SRIOV VFs to create |
