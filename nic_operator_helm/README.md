# NIC OPERATOR HELM project
The NIC OPERATOR HELM project is used to deploy NVIDIA Mellanox network operator using helm charts then tests RDMA traffic using the rping tool.

### Components
The NIC OPERATOR project builds and deploy the following components:
 
* [Kubernetes](https://github.com/kubernetes/kubernetes).
* [Calico](https://www.projectcalico.org/)
* [Mellanox network operator](https://github.com/Mellanox/network-operator).

### Configurations
In addition to the common configurations found at [README.md](./README.md), the sriov project uses the following configurations:
|  Variable |  DEFAULT VALUE |  Comments |
|  ------ |  ------ |  ------ |
|  NIC_OPERATOR_HELM_REPO | -https://github.com/Mellanox/network-operator | nic operator repo to use |
|  NIC_OPERATOR_HELM_BRANCH | master | nic operator branch to use |
|  NIC_OPERATOR_HELM_PR | |  nic operator pull request to pull, adding this will ignore NIC_OPERATOR_HELM_BRANCH |
|  KERNEL_VERSION | 4.15.0-109-generic | system kernel, this is used to pull the right Mellanox OFED container image |
|  OS_DISTRO | ubuntu | system linux distro name, this is used to pull the right Mellanox OFED container image |
|  OS_VERSION | 20.04 | system OS verison, this is used to pull the right Mellanox OFED container image |
|  MACVLAN_NETWORK_DEFAULT_NAME | example-macvlan | This is used to name the macvlan network attackment difinition created by the secondary network feature |
|  NIC_OPERATOR_NAMESPACE | mlnx-network-operator | Used to specify the namespace to deploy the network operator on |
|  NIC_OPERATOR_HELM_NAME | network-operator-helm-ci | Used to specify the helm package name of the operator |
|  OFED_DRIVER_IMAGE | ofed-driver | The OFED driver container image name to pull |
|  OFED_DRIVER_REPO | harbor.mellanox.com/cloud-orchestration | The OFED driver container image repo to pull the image from. P.S. The default repo is not public, the `mellanox` repo should be used instead |
|  OFED_DRIVER_VERSION | 5.0-2.1.8.0 | The OFED driver version to pull, this will be appended to the `OFED_DRIVER_IMAGE` to pull the right image from `OFED_DRIVER_REPO` |
|  DEVICE_PLUGIN_IMAGE | k8s-rdma-shared-dev-plugin  | The RDMA shared device plugin image name |
|  DEVICE_PLUGIN_REPO | harbor.mellanox.com/cloud-orchestration | The RDMA shared device plugin image repo to pull the image from |
|  DEVICE_PLUGIN_VERSION | latest |  The image version (tag) to pull |
|  SECONDARY_NETWORK_MULTUS_IMAGE | multus | The secondary network feature multus image name |
|  SECONDARY_NETWORK_MULTUS_REPO | harbor.mellanox.com/cloud-orchestration | The secondary network feature multus image repo |
|  SECONDARY_NETWORK_MULTUS_VERSION | latest | The secondary network feature multus image version (tag) |
|  SECONDARY_NETWORK_CNI_PLUGINS_IMAGE | containernetworking-plugins | The secondary network feature CNI plugin image name |
|  SECONDARY_NETWORK_CNI_PLUGINS_REPO | harbor.mellanox.com/cloud-orchestration | The secondary network feature CNI plugin image repo |
|  SECONDARY_NETWORK_CNI_PLUGINS_VERSION | latest | The secondary network feature CNI plugin image version (tag) |
|  SECONDARY_NETWORK_IPAM_PLUGIN_IMAGE | whereabouts | The secondary network feature IPAM plugin image name |
|  SECONDARY_NETWORK_IPAM_PLUGIN_REPO | harbor.mellanox.com/cloud-orchestration | The secondary network feature IPAM plugin image repo |
|  SECONDARY_NETWORK_IPAM_PLUGIN_VERSION | latest | The secondary network feature IPAM plugin image version (tag) |

>__NOTE__: In the current implementation of the CI, The CI will try to configure the secondaryNetwork.ipamPlugin.config as if it is trying to configure a whereabouts plugin. This make it not possible to use another IPAM plugin other than the whereabouts plugin.
