#!/bin/bash -x

source ./common/common_functions.sh
source ./common/nic_operator_common.sh

export RECLONE=${RECLONE:-true}
export WORKSPACE=${WORKSPACE:-/tmp/k8s_$$}
export LOGDIR=$WORKSPACE/logs
export ARTIFACTS=$WORKSPACE/artifacts
export TIMEOUT=${TIMEOUT:-180}
export POLL_INTERVAL=${POLL_INTERVAL:-10}


export KERNEL_VERSION=${KERNEL_VERSION:-$(uname -r)}
export OS_DISTRO=${OS_DISTRO:-ubuntu}
export OS_VERSION=${OS_VERSION:-20.04}

function download_and_build {
    status=0
    if [ "$RECLONE" != true ] ; then
        return $status
    fi

    build_nic_operator_image
    let status=status+$?

    return $status
}

function main {
    create_workspace

    pushd $WORKSPACE

    download_and_build
    if [ $? -ne 0 ]; then
        echo "Failed to download and build components"
        exit 1
    fi

    echo "All code in $WORKSPACE"
    echo "All logs $LOGDIR"

    echo "Setup is up and running. Run following to start tests:"
    echo "# WORKSPACE=$WORKSPACE ./nic_operator/nic_operator_image_security_ci_test.sh"

    popd
}

main
exit $?
