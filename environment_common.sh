#!/bin/bash

export SRIOV_INTERFACE=${SRIOV_INTERFACE:-auto_detect}

rdma_mode="shared"

while test $# -gt 0; do
    case "$1" in
    --rdma-mode| -m)
        rdma_mode=$2
        shift
        shift
        ;;
    *)
        echo "No such option!!"
        echo "Exitting ...."
        exit 1
  esac
done

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


load_rdma_modules
let status=status+$?
if [ "$status" != 0 ]; then
    exit $status
fi

enable_rdma_mode "$rdma_mode"
let status=status+$?
if [ "$status" != 0 ]; then
    exit $status
fi
