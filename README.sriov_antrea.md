# SRIOV ANTREA project
The SRIOV ANTREA project is used to deploy Kubernetes on a Mellanox ethernet card (ConnectX cards configured to be ethernet), and configure the network to use SRIOV based network, and use the antrea project as the main CNI.

### Components
The SRIOV ANTREA project builds and deploy the following components:
 
* [Kubernetes](https://github.com/kubernetes/kubernetes).
* [Multus](https://github.com/intel/multus-cni).
* [Container networking plugins](https://github.com/containernetworking/plugins.git).
* [SRIOV network device plugin](https://github.com/intel/sriov-network-device-plugin).
* [vmware antrea project](https://github.com/vmware-tanzu/antrea.git). 

### Configurations
In addition to the common configurations found at [README.md](./README.md), the sriov antrea project uses the following configurations:

|  Variable |  DEFAULT VALUE |  Comments |
|  ------ |  ------ |  ------ |
|  ANTREA_CNI_REPO | https://github.com/vmware-tanzu/antrea.git | antrea project repo to use |
|  ANTREA_CNI_BRANCH | master | antrea project branch to use |
|  ANTREA_CNI_PR | | antrea project pull request to pull, adding this will ignore ANTREA_CNI_BRANCH |
|  SRIOV_NETWORK_DEVICE_PLUGIN_REPO | https://github.com/intel/sriov-network-device-plugin | SRIOV network device plugin repo to use |
|  SRIOV_NETWORK_DEVICE_PLUGIN_BRANCH | master | SRIOV network device plugin branch to build |
|  SRIOV_NETWORK_DEVICE_PLUGIN_PR-'' | SRIOV network device plugin pull request to pull, adding this will ignore SRIOV_NETWORK_DEVICE_PLUGIN_BRANCH |
|  SRIOV_INTERFACE | auto_detect | SRIOV network device, if not specified, the first Mellanox card will be used (does not support ConnectX3) |
|  VFS_NUM | 4 | number of SRIOV VFs to create |
