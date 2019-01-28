#!/usr/bin/env bash

# Provision K8s cluster with Terraform, per Kubespray documentation

set -e

source gitlab.rc  # n.b., Not checked in
source activate.rc
cd inventory/testing
terraform init ../../cellgeni-kubespray/contrib/terraform/openstack
terraform apply -var-file=cluster.tf ../../cellgeni-kubespray/contrib/terraform/openstack
source deactivate
