#!/bin/bash
export RECLONE=${RECLONE:-true}
export WORKSPACE=${WORKSPACE:-/tmp/k8s_$$}
export LOGDIR=$WORKSPACE/logs
export ARTIFACTS=$WORKSPACE/artifacts
export TIMEOUT=${TIMEOUT:-600}
export POLL_INTERVAL=${POLL_INTERVAL:-10}

# can be <latest_stable|master|vA.B.C>
export KUBERNETES_VERSION=${KUBERNETES_VERSION:-latest_stable}
export KUBERNETES_BRANCH=${KUBERNETES_BRANCH:-master}

export MULTUS_CNI_REPO=${MULTUS_CNI_REPO:-https://github.com/intel/multus-cni}
export MULTUS_CNI_BRANCH=${MULTUS_CNI_BRANCH:-master}
# ex MULTUS_CNI_PR=345 will checkout https://github.com/intel/multus-cni/pull/345
export MULTUS_CNI_PR=${MULTUS_CNI_PR:-''}

export PLUGINS_REPO=${PLUGINS_REPO:-https://github.com/containernetworking/plugins.git}
export PLUGINS_BRANCH=${PLUGINS_BRANCH:-master}
export PLUGINS_BRANCH_PR=${PLUGINS_BRANCH_PR:-''}

export GOPATH=${WORKSPACE}
export PATH=/usr/local/go/bin/:$GOPATH/src/k8s.io/kubernetes/third_party/etcd:$PATH

export CNI_BIN_DIR=${CNI_BIN_DIR:-/opt/cni/bin/}
export CNI_CONF_DIR=${CNI_CONF_DIR:-/etc/cni/net.d/}
export ALLOW_PRIVILEGED=${ALLOW_PRIVILEGED:-true}
export NET_PLUGIN=${NET_PLUGIN:-cni}

export KUBE_ENABLE_CLUSTER_DNS=${KUBE_ENABLE_CLUSTER_DNS:-false}
export API_HOST=$(hostname)
export HOSTNAME_OVERRIDE=$(hostname).$(hostname -y)
export EXTERNAL_HOSTNAME=$(hostname).$(hostname -y)
export API_HOST_IP=$(hostname -I | awk '{print $1}')
export KUBELET_HOST=$(hostname -I | awk '{print $1}')
export KUBECONFIG=${KUBECONFIG:-/var/run/kubernetes/admin.kubeconfig}

# generate random network
N=$((1 + RANDOM % 128))
export NETWORK=${NETWORK:-"192.168.$N"}

echo "Working in $WORKSPACE"
mkdir -p $WORKSPACE
mkdir -p $LOGDIR
mkdir -p $ARTIFACTS

pushd $WORKSPACE

echo "Get CPU architechture"
export ARCH="amd"
if [[ $(uname -a) == *"ppc"* ]]; then
   export ARCH="ppc"
fi



##################################################
##################################################
###############   Functions   ####################
##################################################
##################################################


k8s_build(){
    status=0
    echo "Download K8S"
    rm -f /usr/local/bin/kubectl
    if [ ${KUBERNETES_VERSION} == 'latest_stable' ]; then
        export KUBERNETES_VERSION=$(curl -s https://storage.googleapis.com/kubernetes-release/release/stable.txt)
    fi
    rm -rf $GOPATH/src/k8s.io/kubernetes

    go get -d k8s.io/kubernetes

    pushd $GOPATH/src/k8s.io/kubernetes
    git checkout ${KUBERNETES_VERSION}
    git log -p -1 > $ARTIFACTS/kubernetes.txt

    make clean

    let status=status+$?
    if [ "$status" != 0 ]; then
        echo "Failed to build K8S ${KUBERNETES_VERSION}: Failed to clean k8s dir."
        return $status
    fi

    make

    let status=status+$?
    if [ "$status" != 0 ]; then
        echo "Failed to build K8S ${KUBERNETES_VERSION}: Failed to make."
        return $status
    fi

    cp _output/bin/kubectl /usr/local/bin/kubectl

    kubectl version --client
    let status=status+$?
    if [ "$status" != 0 ]; then
        echo "Failed to run kubectl please fix the error above!"
        return $status
    fi

    go get -u github.com/tools/godep

    let status=status+$?
    if [ "$status" != 0 ]; then
        echo "Failed to clone godep"
        return $status
    fi

    go get -u github.com/cloudflare/cfssl/cmd/...

    let status=status+$?
    if [ "$status" != 0 ]; then
        echo 'Failed to clone github.com/cloudflare/cfssl/cmd/...'
        return $status
    fi

    popd
}

k8s_run(){
    status=0
    $GOPATH/src/k8s.io/kubernetes/hack/install-etcd.sh
    screen -S multus_kube -d -m bash -x $GOPATH/src/k8s.io/kubernetes/hack/local-up-cluster.sh
    let status=status+$?
    if [ "$status" != 0 ]; then
        echo "Failed to screen the k8s cluster!"
        return $status
    fi

    kubectl get pods
    rc=$?
    let stop=$(date '+%s')+$TIMEOUT
    d=$(date '+%s')
    while [ $d -lt $stop ]; do
       echo "Wait until K8S is up"
       kubectl get pods
       rc=$?
       d=$(date '+%s')
       sleep $POLL_INTERVAL
       if [ $rc -eq 0 ]; then
           echo "K8S is up and running"
           return 0
      fi
    done
    echo "K8S failed to run in $TIMEOUT sec"
    return 1
}

network_plugins_install(){
    status=0
    echo "Download $PLUGINS_REPO"
    rm -rf $WORKSPACE/plugins
    git clone $PLUGINS_REPO $WORKSPACE/plugins
    pushd $WORKSPACE/plugins
    if test ${PLUGINS_PR}; then
        git fetch --tags --progress ${PLUGINS_REPO} +refs/pull/*:refs/remotes/origin/pr/*
        git pull origin pull/${PLUGINS_PR}/head
        let status=status+$?
        if [ "$status" != 0 ]; then
            echo "Failed to fetch container networking pull request #${PLUGINS_PR}!!"
            return $status
        fi
    elif test $PLUGINS_BRANCH; then
        git checkout $PLUGINS_BRANCH
        if [ "$status" != 0 ]; then
            echo "Failed to switch to container networking branch ${PLUGINS_BRANCH}!!"
            return $status
        fi
    fi
    git log -p -1 > $ARTIFACTS/plugins-git.txt
    bash ./build_linux.sh
    let status=status+$?
    if [ "$status" != 0 ]; then
        echo "Failed to build $PLUGINS_REPO $PLUGINS_BRANCH"
        return $status
    fi

    \cp bin/* $CNI_BIN_DIR/
    popd
}

multus_install(){
    status=0
    echo "Download $MULTUS_CNI_REPO"
    rm -rf $WORKSPACE/multus-cni
    git clone $MULTUS_CNI_REPO $WORKSPACE/multus-cni
    pushd $WORKSPACE/multus-cni
    # Check if part of Pull Request and
    if test ${MULTUS_CNI_PR}; then
        git fetch --tags --progress $MULTUS_CNI_REPO +refs/pull/*:refs/remotes/origin/pr/*
        git pull origin pull/${MULTUS_CNI_PR}/head
        let status=status+$?
        if [ "$status" != 0 ]; then
            echo "Failed to fetch multus pull request #${MULTUS_CNI_PR}!!"
            return $status
        fi
    elif test $MULTUS_CNI_BRANCH; then
        git checkout $MULTUS_CNI_BRANCH
        let status=status+$?
        if [ "$status" != 0 ]; then
            echo "Failed to switch to multus branch ${MULTUS_CNI_BRANCH}!!"
            return $status
        fi
    fi

    ./build
    let status=status+$?
    if [ "$status" != 0 ]; then
        echo "Failed to build multus!!"
        return $status
    fi
    cp bin/multus /opt/cni/bin/

    git log -p -1 > $ARTIFACTS/multus-cni-git.txt
    popd
}

multus_configuration() {
    status=0
    echo "Configure Multus"
    date
    sleep 30
    sed -i 's/\/etc\/cni\/net.d\/multus.d\/multus.kubeconfig/\/var\/run\/kubernetes\/admin.kubeconfig/g' $WORKSPACE/multus-cni/images/multus-daemonset.yml

    kubectl create -f $WORKSPACE/multus-cni/images/multus-daemonset.yml

    kubectl -n kube-system get ds
    rc=$?
    let stop=$(date '+%s')+$TIMEOUT
    d=$(date '+%s')
    while [ $d -lt $stop ]; do
       echo "Wait until multus is ready"
       ready=$(kubectl -n kube-system get ds |grep kube-multus-ds-${ARCH}|awk '{print $4}')
       rc=$?
       kubectl -n kube-system get ds
       d=$(date '+%s')
       sleep $POLL_INTERVAL
       if [ $ready -eq 1 ]; then
           echo "System is ready"
           break
      fi
    done
    if [ $d -gt $stop ]; then
        kubectl -n kube-system get ds
        echo "kube-multus-ds-${ARCH}64 is not ready in $TIMEOUT sec"
        return 1
    fi

    multus_config=$CNI_CONF_DIR/99-multus.conf
    cat > $multus_config <<EOF
    {
        "cniVersion": "0.3.0",
        "name": "macvlan-network",
        "type": "macvlan",
        "mode": "bridge",
          "ipam": {
                "type": "host-local",
                "subnet": "${NETWORK}.0/24",
                "rangeStart": "${NETWORK}.100",
                "rangeEnd": "${NETWORK}.216",
                "routes": [{"dst": "0.0.0.0/0"}],
                "gateway": "${NETWORK}.1"
            }
        }
EOF
    cp $multus_config $ARTIFACTS
    return $?
}

function load_rdma_modules {
    status=0
    if [ $SRIOV_INTERFACE == 'auto_detect' ]; then
        export SRIOV_INTERFACE=$(ls -l /sys/class/net/ | grep $(lspci |grep Mellanox | grep MT27800|head -n1|awk '{print $1}') | awk '{print $9}')
    fi
    echo 0 > /sys/class/net/$SRIOV_INTERFACE/device/sriov_numvfs
    sleep 5

    if [[ -n "$(lsmod | grep rdma_ucm)" ]]; then
        modprobe -r rdma_ucm
        if [ "$?" != "0" ]; then
            echo "Warning: faild to remove the rdma_ucm module"
        fi
        sleep 2
    fi

    if [[ -n "$(lsmod | grep rdma_cm)" ]]; then
        modprobe -r rdma_cm
        if [ "$?" != "0" ]; then
            echo "Warning: Failed to remove rdma_cm module"
        fi
        sleep 2
    fi
    modprobe rdma_cm
    let status=status+$?
    if [ "$status" != 0 ]; then
        echo "Failed to load rdma_cm module"
        return $status
    fi
    modprobe rdma_ucm
    let status=status+$?
    if [ "$status" != 0 ]; then
        echo "Failed to load rdma_ucm module"
        return $status
    fi

    return $status
}

function enable_rdma_mode {
    local_mode=$1
    if [[ -z "$(rdma system | grep $local_mode)" ]]; then
        rdma system set netns "$local_mode"
        let status=status+$?
        if [ "$status" != 0 ]; then
            echo "Failed to set rdma to $local_mode mode"
            return $status
        fi
    fi
}

function deploy_calico {
    rm -rf /etc/cni/net.d/00*
    wget https://docs.projectcalico.org/manifests/calico.yaml -P "$ARTIFACTS"/
    kubectl create -f "$ARTIFACTS"/calico.yaml

    wait_pod_state "calico-node" "Running"

    sleep 20

    # abdallahyas: Since we know that the calico creates a cni conf file with a name starting 
    # with 10* which should be the first alphabetical file after the deleted 00* file, restarting 
    # the multus pod will make the multus configure the calico as the primary network.
    restart_multus_pod
}

function create_macvlan_net {
    local macvlan_file="${ARTIFACTS}/macvlan-net.yaml"

    if [ $SRIOV_INTERFACE == 'auto_detect' ]; then
        export SRIOV_INTERFACE=$(ls -l /sys/class/net/ | grep $(lspci |grep Mellanox | grep -Ev 'MT27500|MT27520' | head -n1 | awk '{print $1}') | awk '{print $9}')
    fi

    if [[ ! -f "$macvlan_file" ]];then
        echo "ERROR: Could not find the macvlan file in ${ARTIFACTS}!"
        exit 1
    fi
    replace_placeholder REPLACE_INTERFACE "$SRIOV_INTERFACE" "$macvlan_file"
    replace_placeholder REPLACE_NETWORK "$NETWORK" "$macvlan_file"
    kubectl create -f "$macvlan_file"
    return $?
}

function restart_multus_pod {
    local multus_pod_name=$(kubectl get pods -A -o name | grep multus | cut -d'/' -f2)

    if [[ -z "$multus_pod_name" ]];then
        return 0
    fi

    local multus_pod_namespace=$(kubectl get pods -A -o wide | grep "$multus_pod_name" | awk '{print $1}')

    kubectl delete pod -n $multus_pod_namespace $multus_pod_name
}

function replace_placeholder {
    local placeholder=$1
    local new_value=$2
    local file=$3
    echo "Changing \"$placeholder\" into \"$new_value\" in $file"
    sed -i "s;$placeholder;$new_value;" $file
}

function wait_pod_state {
    pod_name="$1"
    state="$2"
    let stop=$(date '+%s')+$TIMEOUT
    d=$(date '+%s')
    while [ $d -lt $stop ]; do
        echo "Waiting for pod to become $state"
        pod_status=$(kubectl get pods -A | grep "$pod_name" | grep "$state")
        if [ -n "$pod_status" ]; then
            return 0
        fi
        kubectl get pods -A| grep "$pod_name"
        sleep ${POLL_INTERVAL}
        d=$(date '+%s')
    done
    echo "Error $pod_name is not up"
    return 1
}


function deploy_k8s_with_multus {

    network_plugins_install
    let status=status+$?
    if [ "$status" != 0 ]; then
        echo "Failed to install container networking plugins!!"
        popd
        return $status
    fi

    multus_install
    let status=status+$?
    if [ "$status" != 0 ]; then
        echo "Failed to clone multus!!"
        popd
        return $status
    fi

    k8s_build
    let status=status+$?
    if [ "$status" != 0 ]; then
        echo "Failed to build Kubernetes!!"
        popd
        return $status
    fi

    k8s_run
    let status=status+$?
    if [ "$status" != 0 ]; then
        echo "Failed to run Kubernetes!!"
        popd
        return $status
    fi

    multus_configuration
    let status=status+$?
    if [ "$status" != 0 ]; then
        echo "Failed to run multus!!"
        popd
        return $status
    fi
}
