# Kubernetes Tests
CI for deploying Kubernetes with Multus, SRIOV CNI, and Device Plugin.

Running Installation of K8S, Multus e.t.c

    # ./multus_sriov_cni_install.sh

Running Tests

    # WORKSPACE_K8S=$WORKSPACE_K8S ./multus_sriov_cni_test.sh

Stopping K8S

    # WORKSPACE_K8S=$WORKSPACE_K8S ./multus_sriov_cni_stop.sh
