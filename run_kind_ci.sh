#!/bin/bash

set -e

KIND_CI_PROJECTS=("sriov-cni" "sriov-ib" "antrea" "ipoib" "network-operator" "antrea")
KIND_CI_PHASES=("prepare-ci-environment" "deploy-kind" "utilities" "deploy-project" "test" "undeploy-project" "undeploy-kind")
# SUPPORTED_PHASES is temporally used until all phases are supported
SUPPORTED_PHASES=("prepare-ci-environment" "deploy-kind")
export PHASES_TO_RUN=("${SUPPORTED_PHASES[@]}")

usage() {
  echo "usage: run_kind_ci.sh [[--project <name>] [--skip-phases <phases>] [--num-workers <num>]"
  echo "                       [--kind-config <conf-fil>] [--kubeconfig <path>]  [-h]]"
  echo ""
  echo "--project              Project to run CI: ${KIND_CI_PROJECTS[*]}"
  echo "                       Required field"
  echo "--skip-phases          Comma separated phases, phases: ${KIND_CI_PHASES[*]}"
  echo "--num-workers          Number of worker nodes. DEFAULT: 2 worker"
  echo "--kind-config          Kind configuration file, if provided skip rendering related parameters"
  echo "                       if provided, ignores rendering related parameters (num-workers)"
  echo "--kubeconfig           KUBECONFIG for kind cluster"
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
  for phase in "${SUPPORTED_PHASES[@]}"; do
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
    --skip-phases)
      shift
      parse_skip_phases $1
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
  # Set default values
  export WORKSPACE=${WORKSPACE:-"/tmp/kind_ci/$PROJECT"}
  export KIND_NUM_WORKER=${KIND_NUM_WORKER:-2}
  export KUBECONFIG=${KUBECONFIG:-$HOME/admin.conf}
}

print_params() {
  echo "Using these parameters to KIND CI"
  echo ""
  echo "WORKSPACE       = ${WORKSPACE}"
  echo "PHASES_TO_RUN   = ${PHASES_TO_RUN[*]}"
  echo "PROJECT         = ${PROJECT}"
  echo "KIND_NUM_WORKER = ${KIND_NUM_WORKER}"
  echo "KIND_CONFIG     = ${KIND_CONFIG}"
  echo "KUBECONFIG      = ${KUBECONFIG}"
  echo ""
}

parse_args "$@"
set_default_params
print_params
for phase in "${PHASES_TO_RUN[@]}"; do
  echo "=============================="
  echo "Running phase $phase"
  ansible-playbook --inventory ansible/inventory/hosts "ansible/$phase.yaml" -vv
done

echo "Finished running Kind CI"
