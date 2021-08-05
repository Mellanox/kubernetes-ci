#!/bin/bash
set -x

export LOGDIR=$WORKSPACE/logs
export ARTIFACTS=$WORKSPACE/artifacts


function main {
    mkdir -p $WORKSPACE
    mkdir -p $LOGDIR
    mkdir -p $ARTIFACTS

    docker image rm mellanox/network-operator
    echo "All confs $ARTIFACTS"
}

main

