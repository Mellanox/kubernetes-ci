#!/bin/bash

export WORKSPACE=${WORKSPACE:-/tmp/k8s_$$}
export LOGDIR=$WORKSPACE/logs
export ARTIFACTS=$WORKSPACE/artifacts

export TIMEOUT=${TIMEOUT:-180}


function test_image {
    echo "Scanning Network Operator image for security vulnerability..."
    echo ""
    git clone https://ikolodiazhny:${gitlab_token}@gitlab-master.nvidia.com/sectooling/scanning/contamer.git
    virtualenv .venv
    source .venv/bin/activate
    cd contamer

    pip3 install -r requirements.txt
    let status=$status+$?
    if [ "$status" != 0 ]; then
        echo "Error: Failed install Contamer dependencies!!"
        return $status
    fi

    python3 contamer.py -ls mellanox/network-operator:latest
    let status=$status+$?
    if [ "$status" != 0 ]; then
        echo "Error: Contamer scanning failed!!"
        return $status
    fi


    echo "test_image test success!!!"
    echo ""
    return 0
}


function exit_code {
    rc="$1"
    echo "All logs $LOGDIR"
    echo "All confs $ARTIFACTS"
    exit $status
}

function main {

    status=0

    mkdir -p $WORKSPACE
    mkdir -p $LOGDIR
    mkdir -p $ARTIFACTS

    pushd $WORKSPACE

    test_image
    let status=status+$?
    if [ "$status" != 0 ]; then
        echo "Error: Test Deleting Network Operator failed!"
        exit_code $status
    fi

    popd

    echo ""
    echo "All test succeeded!!"
    echo ""
}

main
exit_code $status

