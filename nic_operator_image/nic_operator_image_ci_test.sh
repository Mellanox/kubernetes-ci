#!/bin/bash

export WORKSPACE=${WORKSPACE:-/tmp/k8s_$$}
export LOGDIR=$WORKSPACE/logs
export ARTIFACTS=$WORKSPACE/artifacts

export TIMEOUT=${TIMEOUT:-180}


function test_image_exists {
    echo "Testing Network Operator image is built..."
    echo ""

    let images=`docker image ls | grep mellanox/network-operator | wc -l`

    if [ "$images" == 0 ]; then
        echo "Error: mellanox/network-operator image is not found!"
        return 1
    fi


    echo "test_image_exists  test success!!!"
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

    test_image_exists
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

