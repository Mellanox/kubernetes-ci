[![Build status](http://13.74.249.42:8080/job/CNI-sriov-Daily/badge/icon?subject=sriov)](http://13.74.249.42:8080/job/CNI-sriov-Daily/)     [![Build Status](http://13.74.249.42:8080/job/CNI-ipoib-Daily/badge/icon?subject=ipoib)](http://13.74.249.42:8080/job/CNI-ipoib-Daily)     [![Build Status](http://13.74.249.42:8080/job/CNI-sriov_ib-Daily/badge/icon?subject=sriov_ib)](http://13.74.249.42:8080/job/CNI-sriov_ib-Daily/)    [![Build Status](http://13.74.249.42:8080/job/CNI-sriov_antrea-Daily/badge/icon?subject=sriov_antrea)](http://13.74.249.42:8080/job/CNI-sriov_antrea-Daily)
# Mellanox Kubernetes CIs
A repo to hold Mellanox Kubernetes CIs scripts.

### CI projects
The CIs are divided into projects depending on the wanted tests, the currently supported projects are:

* `sriov`: tests deploying Kubernetes with sriov on top of Mellanox Ethernet card.
* `sriov_ib`: tests deploying Kubernetes with sriov on top of Mellanox Infiniband card.
* `sriov_antrea`: tests deploying Kubernetes with sriov using the vmware-tenzu/antrea project.
* `ipoib`: tests deploying Kubernetes on top of Mellanox Infiniband card.

### CIs workflow
Any CI execution runs three scripts: the install script, the test script, and the stop script:

* `<project>_cni_install.sh`: the install script is used to build the latest versions of the components used in the project, including the Kubernetes.
* `<project>_cni_test.sh`: the test script tests the functionality of the project, this is deferent depending on the project.
* `cni_stop.sh`: the stop script stops the project components and do cache and images cleanup.

### Configuration
The projects use environment variables to configure their components. Each project has its own set of configurations, but there are some common configurations that all the projects use, those parameters should be exported to environment in case they are needed to change, following are the common configuration of the CIs:

|  Variable |  DEFAULT VALUE |  Comments |
|  ------ |  ------ |  ------ |
|RECLONE | true | whether or not to reclone projects in case of single workspace |
|WORKSPACE | /tmp/k8s_$$ | the directory to build the projects components in, $$ is a random number |
|TIMEOUT | 300 | timeout time for test scripts |
|POLL_INTERVAL | 10 | the interval at which the test scripts try the tests in case of failure |
|KUBERNETES_VERSION | latest_stable | the kubernetes version (or branch) to build |
|MULTUS_CNI_REPO | https://github.com/intel/multus-cni | multus cni repo URL |
|MULTUS_CNI_BRANCH | master | multus cni branch to build |
|MULTUS_CNI_PR || multus cni pr to pull, if this is used the MULTUS_CNI_BRANCH is ignored |
|PLUGINS_REPO | https://github.com/containernetworking/plugins.git | containernetworking repo URL |
|PLUGINS_BRANCH | master | containernetworking branch to build |
|PLUGINS_BRANCH_PR || containernetworking cni pr to pull, if this is used the PLUGINS_BRANCH is ignored |
|GOPATH | ${WORKSPACE} ||
|PATH | /usr/local/go/bin/:$GOPATH/src/k8s.io/kubernetes/third_party/etcd:$PATH ||
|CNI_BIN_DIR | /opt/cni/bin/ | this is used to configure Kubernetes local_cluser_up.sh CNI_BIN_DIR |
|CNI_CONF_DIR | /etc/cni/net.d/ | this is used to configure Kubernetes local_cluser_up.sh CNI_CONF_DIR |
|ALLOW_PRIVILEGED | true | this is used to configure Kubernetes local_cluser_up.sh ALLOW_PRIVILEGED |
|NET_PLUGIN | cni | this is used to configure Kubernetes local_cluser_up.sh NET_PLUGIN |
|KUBE_ENABLE_CLUSTER_DNS | false | this is used to configure Kubernetes local_cluser_up.sh KUBE_ENABLE_CLUSTER_DNS |
|API_HOST | $(hostname) | this is used to configure Kubernetes local_cluser_up.sh API_HOST |
|HOSTNAME_OVERRIDE | hostname | this is used to configure Kubernetes local_cluser_up.sh HOSTNAME_OVERRIDE |
|EXTERNAL_HOSTNAME | hostname | this is used to configure Kubernetes local_cluser_up.sh EXTERNAL_HOSTNAME |
|API_HOST_IP | host ip | this is used to configure Kubernetes local_cluser_up.sh API_HOST_IP |
|KUBELET_HOST | host ip | this is used to configure Kubernetes local_cluser_up.sh KUBELET_HOST |
|KUBECONFIG | /var/run/kubernetes/admin.kubeconfig | this is used to configure Kubernetes local_cluser_up.sh KUBECONFIG |
|NETWORK | "192.168.$N" | this is used to setup the macvlan network range, N is randomly generated |

For more information on each project, please see the related project README.
