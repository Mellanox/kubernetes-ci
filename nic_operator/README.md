# NIC OPERATOR project
The NIC OPERATOR project is used to deploy Kubernetes on a Mellanox ethernet card (ConnectX cards configured to be ethernet), and configure the network to use two networks: the first is valico as the primary network, the second is macvlan as the RDMA workload network.

### Components
The NIC OPERATOR project builds and deploy the following components:
 
* [Kubernetes](https://github.com/kubernetes/kubernetes).
* [Multus](https://github.com/intel/multus-cni).
* [Container networking plugins](https://github.com/containernetworking/plugins.git).
* [Mellanox network operator](https://github.com/Mellanox/network-operator).

### Configurations
In addition to the common configurations found at [README.md](./README.md), the sriov project uses the following configurations:
|  Variable |  DEFAULT VALUE |  Comments |
|  ------ |  ------ |  ------ |
|  NIC_OPERATOR_REPO | -https://github.com/Mellanox/network-operator | nic operator repo to use |
|  NIC_OPERATOR_BRANCH | master | nic operator branch to use |
|  NIC_OPERATOR_PR | |  nic operator pull request to pull, adding this will ignore NIC_OPERATOR_BRANCH |
|  KERNEL_VERSION | 4.15.0-109-generic | system kernel, this is used to pull the right Mellanox OFED container image |
|  OS_DISTRO | ubuntu | system linux distro name, this is used to pull the right Mellanox OFED container image |
|  OS_VERSION | 4 | system OS verison, this is used to pull the right Mellanox OFED container image |
