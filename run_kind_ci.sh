#!/bin/bash

set -e

ansible_dir=$(dirname $0)/ansible

KIND_CI_PROJECTS=("sriov-cni" "sriov-ib" "antrea" "ipoib" "network-operator" "antrea" "ovn-kubernetes"\
                  "sriov-network-operator" "nic-operator-kind" "nic-operator-helm")
KIND_CI_PHASES=("prepare-ci-environment" "deploy-kind" "utilities" "deploy-project" "test" "undeploy-project" "undeploy-kind")
export PHASES_TO_RUN=("${KIND_CI_PHASES[@]}")

usage() {
  echo "usage: run_kind_ci.sh [[--project <name>] [--phases <phases>] [--skip-phases <phases>]"
  echo "                       [--num-workers <num>] [--kind-config <conf-fil>] [--kubeconfig <path>]"
  echo "                       [--kind-node-image <image>] [--interfaces-type <interfaces-type>] [-h]]"
  echo ""
  echo "--project              Project to run CI: ${KIND_CI_PROJECTS[*]}"
  echo "                       Required field"
  echo "--phases               Comma separated phases to run, if presented ignores --skip-phases. phases: ${KIND_CI_PHASES[*]}"
  echo "--skip-phases          Comma separated phases, phases: ${KIND_CI_PHASES[*]}"
  echo "--num-workers          Number of worker nodes. DEFAULT: 2 worker"
  echo "--pf-per-worker        How many PFs to switch for each worker node"
  echo "--interfaces-type      Specify the interfaces type to switch into the kind node. support: "eth", "ib", or "both". Default: eth"
  echo "--kind-config          Kind configuration file, if provided skip rendering related parameters"
  echo "                       if provided, ignores rendering related parameters (num-workers)"
  echo "--kubeconfig           KUBECONFIG for kind cluster"
  echo "--kind-node-image      Kind node image to use"
  echo "--pr                   Pull Request number"
  echo ""
}

containsElement() {
  local value="$1"
  local list="$2"
  shift
  for e in $list; do
    [[ "$e" == "$value" ]] && return 0
  done

  return 1
}

parse_phases() {
  PHASES=$1
  IFS="," read -a PHASES <<<"$1"
  for phase in "${PHASES[@]}"; do
    if ! containsElement "$phase" "${KIND_CI_PHASES[*]}"; then
      echo "Unknown phase $phase"
      usage
      exit 1
    fi
  done

  PHASES_TO_RUN=()
  for phase in "${KIND_CI_PHASES[@]}"; do
    if containsElement "$phase" "${PHASES[*]}"; then
      PHASES_TO_RUN+=("$phase")
    fi
  done
}

parse_skip_phases() {
  SKIP_PHASES=$1
  IFS="," read -a SKIP_PHASES <<<"$1"
  for phase in "${SKIP_PHASES[@]}"; do
    if ! containsElement "$phase" "${KIND_CI_PHASES[*]}"; then
      echo "Unknown phase $phase"
      usage
      exit 1
    fi
  done

  PHASES_TO_RUN=()
  for phase in "${KIND_CI_PHASES[@]}"; do
    if ! containsElement "$phase" "${SKIP_PHASES[*]}"; then
      PHASES_TO_RUN+=("$phase")
    fi
  done
}

parse_args() {
  while [ "$1" != "" ]; do
    case $1 in
    --project)
      shift
      project=$1
      containsElement "$project" "${KIND_CI_PROJECTS[*]}"
      if [[ "$?" != "0" ]]; then
        echo "Unknown project ci $project"
        usage
        exit 1
      fi
      export PROJECT=$project
      ;;
    --phases)
      shift
      parse_phases $1
      ;;
    --skip-phases)
      shift
      if [[ ${PHASES} == "" ]]; then
        parse_skip_phases $1
      fi
      ;;
    --num-workers)
      shift
      if ! [[ "$1" =~ ^[0-9]+$ ]]; then
        echo "Invalid num-workers: $1"
        usage
        exit 1
      fi
      export KIND_NUM_WORKER=$1
      ;;
    --pf-per-worker)
      shift
      if ! [[ "$1" =~ ^[0-9]+$ ]]; then
        echo "Invalid pf-per-worker: $1"
        usage
        exit 1
      fi
      export PF_PER_WORKER=$1
      ;;
    --interfaces-type)
      shift
      export INTERFACES_TYPE="$2"
      ;;
    --kind-config)
      shift
      kind_conf=$1
      if test ! -f "$kind_conf"; then
        echo "$kind_conf does not  exist"
        usage
        exit 1
      fi
      export KIND_CONFIG=$1
      ;;
    --kubeconfig)
      shift
      export KUBECONFIG=$1
      ;;
    --kind-node-image)
      shift
      export KIND_NODE_IMAGE=$1
      ;;
    --pr)
      shift
      if ! [[ "$1" =~ ^[0-9]+$ ]]; then
        echo "Invalid num-workers: $1"
        usage
        exit 1
      fi
      export PULL_REQUEST=$1
      ;;

    -h | --help)
      usage
      exit
      ;;
    *)
      usage
      exit 1
      ;;
    esac
    shift
  done

  # Required parameters
  if [[ "$PROJECT" == "" ]]; then
    echo "--project is required"
    usage
    exit 1
  fi
}

set_default_params() {
  if [[ -e $ansible_dir/projects/$PROJECT/environment.sh ]];then
    source $ansible_dir/projects/$PROJECT/environment.sh
  fi

  # Set default values
  export WORKSPACE=${WORKSPACE:-"/tmp/kind_ci/$PROJECT"}
  export KIND_NUM_WORKER=${KIND_NUM_WORKER:-2}
  export PF_PER_WORKER=${PF_PER_WORKER:-1}
  export KUBECONFIG=${KUBECONFIG:-$HOME/admin.conf}
  export KIND_NODE_IMAGE="${KIND_NODE_IMAGE:-''}"
  export INTERFACES_TYPE=${INTERFACES_TYPE:-"eth"}
}

print_params() {
  echo "Using these parameters to KIND CI"
  echo ""
  echo "WORKSPACE       = ${WORKSPACE}"
  echo "PHASES_TO_RUN   = ${PHASES_TO_RUN[*]}"
  echo "PROJECT         = ${PROJECT}"
  echo "KIND_NUM_WORKER = ${KIND_NUM_WORKER}"
  echo "PF_PER_WORKER   = ${PF_PER_WORKER}"
  echo "KIND_NODE_IMAGE = ${KIND_NODE_IMAGE}"
  echo "KIND_CONFIG     = ${KIND_CONFIG}"
  echo "KUBECONFIG      = ${KUBECONFIG}"
  echo "PULL_REQUEST    = ${PULL_REQUEST}"
  echo "INTERFACES_TYPE = ${INTERFACES_TYPE}"
  echo ""
}

parse_args "$@"
set_default_params
print_params
for phase in "${PHASES_TO_RUN[@]}"; do
  echo "=============================="
  echo "Running phase $phase"
  ansible-playbook --inventory $ansible_dir/inventory/hosts \
                  "$ansible_dir/$phase.yaml" \
                  -e @$ansible_dir/ci_vars/kind_ci.yaml -vv \
                  -e ansible_python_interpreter=/usr/bin/python3
done

echo "Finished running Kind CI"
