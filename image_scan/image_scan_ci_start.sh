#!/bin/bash

source ./common/common_functions.sh

export RECLONE=${RECLONE:-true}
export WORKSPACE=${WORKSPACE:-/tmp/k8s_$$}
export LOGDIR=$WORKSPACE/logs
export ARTIFACTS=$WORKSPACE/artifacts
export TIMEOUT=${TIMEOUT:-300}
export POLL_INTERVAL=${POLL_INTERVAL:-10}

export PROJECT_URL=${PROJECT_URL}
export PROJECT_PR=${PROJECT_PR}
export PROJECT_PR_PREFIX=${PROJECT_PR_PREFIX:-'+refs/pull'}
export PROJECT_NAME=${PROJECT_NAME}

export PROJECT_IMAGE_NAME=${PROJECT_IMAGE_NAME}
export PROJECT_IMAGE_BUILD_COMMAND=${PROJECT_IMAGE_BUILD_COMMAND:-\
"TAG=${PROJECT_IMAGE_NAME} make image"}

contamer_dir=$WORKSPACE/contamer

clone_project(){
    local status=0

    if [[ -e ""$WORKSPACE"/"$PROJECT_NAME"" ]];then
        rm -rf "$WORKSPACE"/"$PROJECT_NAME"
    fi

    git clone "${PROJECT_URL}" "$WORKSPACE"/"$PROJECT_NAME"

    pushd $WORKSPACE/"$PROJECT_NAME"

    if [[ -n "${PROJECT_PR}" ]];then
        git fetch --tags --progress ${PROJECT_URL}\
        ${PROJECT_PR_PREFIX}/${PROJECT_PR}/merge:\
refs/remotes/origin/pr/${PROJECT_PR}/merge
        let status=$status+$?
        git checkout pr/${PROJECT_PR}/merge
        let status=$status+$?
    fi

    git log -p -1 > $ARTIFACTS/${PROJECT_NAME}-git.txt

    popd

    return $status
}

function clone_contamer {
    if [[ -z ${gitlab_user} ]] || [[ -z ${gitlab_token} ]];then
        echo "Error: gitlab credentials not provided, exiting!"
        return 1
    fi

    git clone https://${gitlab_user}:${gitlab_token}@gitlab-master.nvidia.com/\
sectooling/scanning/contamer.git "$contamer_dir"
}

function install_contamer_dependencies {
    virtualenv .venv
    source .venv/bin/activate
    pushd $contamer_dir

    pip3 install -r requirements.txt
    let status=$status+$?
    if [ "$status" != 0 ]; then
        echo "Error: Failed install Contamer dependencies!!"
        return $status
    fi
    popd
}

function build_image {
    local status=0
    if [[ -z "${PROJECT_IMAGE_NAME}" ]];then
        echo "Error: image name not provided!"
        return 1
    fi

    pushd $WORKSPACE/"$PROJECT_NAME"

    eval ${PROJECT_IMAGE_BUILD_COMMAND}
    let status=$status+$?

    popd

    return $status
}

function clean_image {
    if [[ -z "${PROJECT_IMAGE_NAME}" ]];then
        echo "Error: image name not provided!"
        return 1
    fi

    docker rmi "${PROJECT_IMAGE_NAME}"
    return $?
}

function test_image {
    echo "Scanning ${PROJECT_NAME} image for security vulnerability..."
    echo ""

    pushd $contamer_dir/

    python3 ./contamer.py -ls "${PROJECT_IMAGE_NAME}"
    let status=$status+$?

    if [[ "$status" != "0" ]];then
        echo "Error: Contamer scanning failed!!"
    else
        echo "test_image test success!!!"
    fi

    echo ""
    return "$status"
}

main(){
    local status=0

    create_workspace

    clone_project
    let status=$status+$?
    if [[ "$status" != "0" ]];then
        echo "Error: failed to clone project ${PROJECT_NAME}!"
        return "$status"
    fi

    build_image
    let status=$status+$?
    if [[ "${status}" != "0" ]];then
        echo "Error: failed to build the project image!"
        return "$status"
    fi

    clone_contamer
    let status=$status+$?
    if [[ "${status}" != "0" ]];then
        echo "Error: failed to build the project image!"
        return "$status"
    fi

    install_contamer_dependencies
    let status=$status+$?
    if [[ "${status}" != "0" ]];then
        echo "Error: failed to build the project image!"
        return "$status"
    fi

    test_image
    let status=$status+$?
    if [[ "${status}" != "0" ]];then
        echo "Error: image security scanning failed!"
    fi

    clean_image
    return "$status"
}

global_status=0

main
let global_status=$?
if [[ "${global_status}" != "0" ]];then
    echo "Image security scanning failed!"
else
    echo "Image security scanning suceeded!"
fi

echo "All code in $WORKSPACE"
echo "All logs $LOGDIR"
echo "All confs $ARTIFACTS"

exit $global_status
