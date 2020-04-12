# Kubernetes Tests
CI for deploying Kubernetes with Multus, SRIOV CNI, RDMA CNI and Device Plugin.

### Download and install all the components
```sh
$ ./sriov_cni_install.sh
```
### Run basic test

``` sh
$ ./sriov_cni_test.sh
```

### Stop all the components

```sh
$ ./sriov_cni_stop.sh
```


### Configuration

Those paramateres should be exported to environment
```sh
$ export TIMEOUT=100
```
|  Variable |  DEFAULT VALUE |  Comments |
|  ------ |  ------ |  ------ |
| MACVLAN_INTERFACE | eno1 | Ethernet interface |
| SRIOV_INTERFACE | enp3s0f0 | SR-IOV Interface |
| VFS_NUM | 4 | Number of Virtual Functions to config"
| RECLONE |  true |  reclone the code again from the repo |
| WORKSPACE | /tmp/k8s_$$ |  working directory |
| LOGDIR | $WORKSPACE/logs | folder with all the logs |
| ARTIFACTS | $WORKSPACE/artifacts | folder with configuration artifacts |
| TIMEOUT | 300 |  timeout in seconds for the components to be active |
| POLL_INTERVAL | 10 | Polling interval in seconds to check components |
| KUBERNETES_VERSION | latest_stable | Kubernetes version ex: latest_stable,v1.16.0| |
| KUBERNETES_BRANCH | master | Kubernetes branch |
| MULTUS_CNI_REPO | https://github.com/intel/multus-cni | Multus repo |
| MULTUS_CNI_BRANCH | master | Multus branch |
| MULTUS_CNI_PR | '' | Multus Pull Request. ex MULTUS_CNI_PR=345 will checkout https://github.com/intel/multus-cni/pull/345 |
| SRIOV_CNI_REPO | https://github.com/intel/sriov-cni | SRIOV-CNI repo |
| SRIOV_CNI_BRANCH | master | SRIOV-CNI branch |
| SRIOV_CNI_PR | '' | SRIOV-CNI Pull Request |
| PLUGINS_REPO | https://github.com/containernetworking/plugins.git | PLUGINS repo |
| PLUGINS_BRANCH | master | PLUGINS branch |
| PLUGINS_BRANCH_PR | '' | PLUGINS Pull Request |
| SRIOV_NETWORK_DEVICE_PLUGIN_REPO | https://github.com/intel/sriov-network-device-plugin | SRIOV-NETWORK-DEVICE-PLUGIN repo |
| SRIOV_NETWORK_DEVICE_PLUGIN_BRANCH | master | SRIOV-NETWORK-DEVICE-PLUGINbranch
| SRIOV_NETWORK_DEVICE_PLUGIN_PR | '' | SRIOV-NETWORK-DEVICE-PLUGIN Pull Request |
| RDMA_CNI_REPO | https://github.com/Mellanox/rdma-cni | RDMA repo |
| RDMA_CNI_BRANCH | master | RDMA repo branch |
| RDMA_CNI_PR | '' | RDMA Pull Request. ex RDMA_CNI_PR=345 will checkout https://github.com/Mellanox/rdma-cni/pull/345 |
| GOPATH | $WORKSPACE | |
| PATH | /usr/local/go/bin/:$GOPATH/src/k8s.io/kubernetes/third_party/etcd:$PATH |
| CNI_BIN_DIR | /opt/cni/bin/ | |
| CNI_CONF_DIR | /etc/cni/net.d/ | |
| ALLOW_PRIVILEGED | true | |
| NET_PLUGIN | cni | |
| KUBE_ENABLE_CLUSTER_DNS | false |
| API_HOST | hostname | |
| API_HOST_IP | host ip | |
| KUBECONFIG | /var/run/kubernetes/admin.kubeconfig | |
| NETWORK | 192.168.1 |
