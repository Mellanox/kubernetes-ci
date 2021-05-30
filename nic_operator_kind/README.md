# NIC OPERATOR KIND project
The NIC OPERATOR KIND project is used to deploy and test the NVIDIA Mellanox network operator on a kind cluster. It deploys a kind cluster, switch Mellanox interfaces to the worker node, and perform it designed tests to make sure all network operator functionalities are working as expected.

### Components
The NIC OPERATOR KIND deploys the following components:
 
* Latest kind.
* calico.
* [Mellanox network operator](https://github.com/Mellanox/network-operator).

### Configurations
In addition to the common configurations found at [README.md](./README.md), the sriov project uses the following configurations:
|  Variable |  DEFAULT VALUE |  Comments |
|  ------ |  ------ |  ------ |
|  NIC_OPERATOR_REPO | -https://github.com/Mellanox/network-operator | nic operator repo to use |
|  NIC_OPERATOR_BRANCH | master | nic operator branch to use |
|  NIC_OPERATOR_PR | |  nic operator pull request to pull, adding this will ignore NIC_OPERATOR_BRANCH |
|  OS_DISTRO | ubuntu | system linux distro name, this is used to pull the right Mellanox OFED container image |
|  OS_VERSION | 20 | system OS verison, this is used to pull the right Mellanox OFED container image |
