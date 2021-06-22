# NIC OPERATOR IMAGE project
The NIC OPERATOR IMAGE project is used to verify image build procedure for Network Operator.

### Configurations
In addition to the common configurations found at [README.md](./README.md):
|  Variable |  DEFAULT VALUE |  Comments |
|  ------ |  ------ |  ------ |
|  NIC_OPERATOR_REPO | -https://github.com/Mellanox/network-operator | nic operator repo to use |
|  NIC_OPERATOR_BRANCH | master | nic operator branch to use |
|  NIC_OPERATOR_PR | |  nic operator pull request to pull, adding this will ignore NIC_OPERATOR_BRANCH |
|  OS_DISTRO | ubuntu | system linux distro name, this is used to pull the right Mellanox OFED container image |
|  OS_VERSION | 4 | system OS verison, this is used to pull the right Mellanox OFED container image |
