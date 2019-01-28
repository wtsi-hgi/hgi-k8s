#!/usr/bin/env bash

# Provision K8s cluster with Terraform, per Kubespray documentation

set -eu

WORK_DIR="$(dirname "$(readlink -fn "$0")")"
TERRAFORM_PATH="${WORK_DIR}/cellgeni-kubespray/contrib/terraform/openstack"

main() {
  local inventory
  local -i destroy=0

  while (( $# )); do
    case "$1" in
      "--destroy")
        destroy=1
        ;;

      *)
        if [[ -e "inventory/$1/cluster.tf" ]]; then
          inventory="$1"
        fi
        ;;
    esac

    shift
  done

  if [[ -z "${inventory+x}" ]]; then
    >&2 echo "No inventory specified!"
    >&2 echo "Usage: provision.sh [--destroy] INVENTORY_NAME"
    exit 1
  fi

  source gitlab.rc  # n.b., Not checked in
  source activate.rc
  trap "source deactivate" EXIT

  cd "inventory/${inventory}"

  if ! (( destroy )); then
    # Initialise and deploy
    terraform init "${TERRAFORM_PATH}"
    terraform apply -var-file=cluster.tf "${TERRAFORM_PATH}"

  else
    # Destroy cluster
    terraform destroy -var-file=cluster.tf "${TERRAFORM_PATH}"
  fi
}

main "$@"
