# SRIOV NETWORK OPERATOR CI
The SRIOV NETWORK OPERATOR project is used to deploy Kubernetes on a Mellanox ethernet card (ConnectX cards configured to be ethernet) using kind, deploy the sriov-network-operator project, and run the sriov-network-operator e2e tests on the kind cluster.

### Components
The SRIOV NETWORK OPERATOR project deploy the following components:

* [kind](https://github.com/kubernetes-sigs/kind).
* [Multus](https://github.com/intel/multus-cni).
* [sriov-network-operator](https://github.com/k8snetworkplumbingwg/sriov-network-operator)

### Configurations
In addition to the common configurations found at [README.md](./README.md), the sriov project uses the following configurations:
|  Variable |  DEFAULT VALUE |  Comments |
|  ------ |  ------ |  ------ |
|  SRIOV_NETWORK_OPERATOR_REPO | https://github.com/k8snetworkplumbingwg/sriov-network-operator.git | sriov-network-operator repo to use |
|  SRIOV_NETWORK_OPERATOR_BRANCH | 'master' | sriov-network-operator branch to build |
|  SRIOV_NETWORK_OPERATOR_PR | '' | sriov-network-operator PR to build |
|  SRIOV_CNI_IMAGE | nfvpe/sriov-cni:v2.6 | sriov cni image to use |
|  SRIOV_INFINIBAND_CNI_IMAGE | mellanox/ib-sriov-cni:faa9e36 | the ib-sriov cni iage to use |
|  SRIOV_DEVICE_PLUGIN_IMAGE | quay.io/openshift/origin-sriov-network-device-plugin:4.8 | the sriov-network-device-plugin image to use |
|  SRIOV_NETWORK_CONFIG_DAEMON_IMAGE | mellanox/sriov-operator-daemon:ci | the sriov-operator-daemon image to use |
|  SRIOV_NETWORK_OPERATOR_IMAGE | mellanox/sriov-operator:ci | the sriov-operator image to use |

