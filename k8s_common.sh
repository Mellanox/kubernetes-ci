#!/bin/bash

##################################################
##################################################
##################   input   #####################
##################################################
##################################################


while test $# -gt 0; do
  case "$1" in

    --no-cloning)
        RECLONE=false
        shift
        ;;

    --workspace| -w)
        WORKSPACE=$2
        shift
        shift
        ;;

    --k8s-timeout)
        TIMEOUT=$2
        shift
        shift
        ;;

    --poll-interval)
        POLL_INTERVAL=$2
        shift
        shift
        ;;

    --kubectl-version)
        KUBERNETES_VERSION=$2
        shift
        shift
        ;;

    --k8s-branch)
        KUBERNETES_BRANCH=$2
        shift
        shift
        ;;

    --multus-repo)
        MULTUS_CNI_REPO=$2
        shift
        shift
        ;;

    --multus-branch)
        MULTUS_CNI_BRANCH=$2
        shift
        shift
        ;;

    --multus-pr)
        MULTUS_CNI_PR=$2
        shift
        shift
        ;;

    --plugins-repo)
        PLUGINS_REPO=$2
        shift
        shift
        ;;

    --plugins-branch)
        PLUGINS_BRANCH=$2
        shift
        shift
        ;;

    --plugins-pr)
        PLUGINS_BRANCH_PR=$2
        shift
        shift
        ;;

    --cni-bin-dir)
        CNI_BIN_DIR=$2
        shift
        shift
        ;;

    --cni-conf-dir)
        CNI_CONF_DIR=$2
        shift
        shift
        ;;

    --kube-config-file)
        KUBECONFIG=$2
        shift
        shift
        ;;

    --network-subnet)
        NETWORK=$2
        shift
        shift
        ;;

   --help | -h)
      echo "

	--no-cloning)				Don't reclone repos if they exists in the workspace.

	--workspace| -w) <workspace>		The dir to work in, logs, repos, and config file will be in workspace. Defaulted to /tmp/k8s_$$.

	--k8s-timeout) <k8s timeout>		The timeout value to wait for k8s ti run. Defaulted to 300.

	--poll-interval) <pol interval>		The poll interval to wait between each check for results during the timeout time. Defaulted to 10.

	--kubectl-version) <kubectl version>	The version of the kubectl CLI tool, defaulted to latest_stable, and can be set to master. 

	--k8s-branch) <repo branch>		The branch of the k8s repo to build. Defaulted to master.

	--multus-repo) <multus repo>		The source code repo of the multus plugin. Defaulted to https://github.com/intel/multus-cni.

	--multus-branch) <multus branch>	The branch of the multus repo. Defaulted to master.

	--multus-pr) <multus pr>		If specified, the multus pull request number to use for the plugin.

	--plugins-repo) <plugins repo>		The repo to use for installing the containerNetworking plugins. Defaulted to https://github.com/containernetworking/plugins.git.

	--plugins-branch) <plugins branch>	The branch of the containerNetworking plugins to use. Defaulted to master.

	--plugins-pr) <plugins pr>		The pull request number to use for the containerNetworking.

	--cni-bin-dir) <bin dir>		The directory to use for the cni bin dir, will be passed to the k8s. Defaulted to \"/opt/cni/bin/\".

	--cni-conf-dir) <conf dir>		The cni configuration file to use for the k8s. Defaulted to \"/etc/cni/net.d/\"

	--kube-config-file) <kubeconfig>	The file to save the KUBECONFIG to. Defaulted to \"/var/run/kubernetes/admin.kubeconfig\"

	--network-subnet) <subnet>		The subnet cidr to use for the pods network, used to configure the multus. Defaulted to \"192.168.<random>\". The value should only be the first three octants.

"
      exit 0
      ;;
   
   *)
      echo "No such option!!"
      echo "Exitting ...."
      exit 1
  esac
done

exec 1> >(logger -s -t $(basename $0)) 2>&1


export RECLONE=${RECLONE:-true}
export WORKSPACE=${WORKSPACE:-/tmp/k8s_$$}
export LOGDIR=$WORKSPACE/logs
export ARTIFACTS=$WORKSPACE/artifacts
export TIMEOUT=${TIMEOUT:-300}
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
export API_HOST=$(hostname).$(hostname -y)
export API_HOST_IP=$(hostname -I | awk '{print $1}')
export KUBECONFIG=${KUBECONFIG:-/var/run/kubernetes/admin.kubeconfig}

# generate random network
N=$((1 + RANDOM % 128))
export NETWORK=${NETWORK:-"192.168.$N"}

echo "Working in $WORKSPACE"
mkdir -p $WORKSPACE
mkdir -p $LOGDIR
mkdir -p $ARTIFACTS

cd $WORKSPACE

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

    rm -rf $GOPATH/src/k8s.io/kubernetes

    go get -d k8s.io/kubernetes

    pushd $GOPATH/src/k8s.io/kubernetes
    #git checkout $KUBERNETES_BRANCH
    git log -p -1 > $ARTIFACTS/kubernetes.txt

    make clean

    let status=status+$?
    if [ "$status" != 0 ]; then
        echo "Failed to build K8S $KUBERNETES_BRANCH"
        return $status
    fi

    make

    let status=status+$?
    if [ "$status" != 0 ]; then
        echo "Failed to build K8S $KUBERNETES_BRANCH"
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
        echo 'Failed to clone get github.com/cloudflare/cfssl/cmd/...'
        return $status
    fi

    popd
}

kubectl_download(){
    echo "Download and install kubectl"
    rm -f ./kubectl /usr/local/bin/kubectl
    if [ ${KUBERNETES_VERSION} == 'latest_stable' ]; then
        export KUBERNETES_VERSION=$(curl -s https://storage.googleapis.com/kubernetes-release/release/stable.txt)
        curl -LO https://storage.googleapis.com/kubernetes-release/release/${KUBERNETES_VERSION}/bin/linux/${ARCH}64/kubectl
        let status=status+$?
        if [ "$status" != 0 ]; then
            echo "Failed to get the latest release of kubectl"
            return $status
        fi
        
        mv ./kubectl /usr/local/bin/kubectl
    elif [ ${KUBERNETES_VERSION} == 'master' ]; then
        [ ! -f $GOPATH/src/k8s.io/kubernetes/_output/local/go/bin/kubectl ] && k8s_build
        mv $GOPATH/src/k8s.io/kubernetes/_output/local/go/bin/kubectl /usr/local/bin/kubectl
    else
        curl -LO https://storage.googleapis.com/kubernetes-release/release/${KUBERNETES_VERSION}/bin/linux/${ARCH}64/kubectl
        let status=status+$?
        if [ "$status" != 0 ]; then
            echo "Failed to get kubectl version ${KUBERNETES_VERSION}"
            return $status
        fi
        mv ./kubectl /usr/local/bin/kubectl
    fi

    chmod +x /usr/local/bin/kubectl
    kubectl version --client
    let status=status+$?
    if [ "$status" != 0 ]; then
        echo "Failed to run kubectl please fix the error above!"
        return $status
    fi
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
    exit 1
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
        if [ "$status" != 0 ]; then
            echo "Failed to switch to multus branch ${MULTUS_CNI_BRANCH}!!"
            return $status
        fi
    fi
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
        exit 1
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


##################################################
##################################################
##############   validation   ####################
##################################################
##################################################




##################################################
##################################################
###################   Main   #####################
##################################################
##################################################


k8s_build
let status=status+$?
if [ "$status" != 0 ]; then
    echo "Failed to build Kubernetes!!"
    exit $status
fi

kubectl_download
let status=status+$?
if [ "$status" != 0 ]; then
    echo "Failed to install kubectl!!"
    exit $status
fi

k8s_run
let status=status+$?
if [ "$status" != 0 ]; then
    echo "Failed to run Kubernetes!!"
    exit $status
fi

network_plugins_install
let status=status+$?
if [ "$status" != 0 ]; then
    echo "Failed to install container networking plugins!!"
    exit $status
fi

multus_install
let status=status+$?
if [ "$status" != 0 ]; then
    echo "Failed to clone multus!!"
    exit $status
fi

multus_configuration
let status=status+$?
if [ "$status" != 0 ]; then
    echo "Failed to run multus!!"
    exit $status
fi
