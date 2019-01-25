#!/usr/bin/env bash

# Activate environment for OpenStack API
# Christopher Harrison <ch12@sanger.ac.uk>

# Must be sourced
if [[ "$0" == "${BASH_SOURCE}" ]]; then
  >&2 echo "This must be sourced, rather than executed!"
  exit 1
fi

# GITLAB_URL and GITLAB_TOKEN environment variables must be set
if [[ -z "${GITLAB_URL}" ]] || [[ -z "${GITLAB_TOKEN}" ]]; then
  >&2 echo "GITLAB_URL and GITLAB_TOKEN environment variables are not set!"
  return 1
fi

# Set OS_USERNAME and OS_PASSWORD from Gitlab
get_os_env() {
  {
    # Setup virtual environment, if it doesn't exist
    if ! [[ -d ".venv" ]]; then
      python3 -m venv .venv
    fi

    # Start virtual environment and update requirements, if neccessary
    source .venv/bin/activate
    pip install -U gitlabbuildvariables
  } >/dev/null 2>&1

  gitlab-get-variables --url "${GITLAB_URL}" --token "${GITLAB_TOKEN}" hgi/hgi-systems \
  | jq -r '"export OS_USERNAME=\"" + .ZETA_OS_USERNAME + "\"\nexport OS_PASSWORD=\"" + .ZETA_OS_PASSWORD + "\""'

  deactivate >/dev/null 2>&1
}
source <(get_os_env)

# Set further OpenStack API environment variables
export OS_AUTH_URL="https://zeta.internal.sanger.ac.uk:13000/v3"

export OS_PROJECT_ID="4c4eee22a6bd4355b1318e7a46be55a1"
export OS_TENANT_ID="${OS_PROJECT_ID}"
export OS_PROJECT_NAME="hgi-nextflow"

export OS_USER_DOMAIN_NAME="Default"
export OS_PROJECT_DOMAIN_ID="default"
export OS_REGION_NAME="regionOne"
export OS_INTERFACE="public"
export OS_IDENTITY_API_VERSION=3
