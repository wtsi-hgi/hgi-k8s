# HGI Kubernetes

This repo provides everything necessary to provision a Kubernetes
cluster on Sanger's OpenStack and deploy the following services:

* JupyterHub

K8s deployment is done using a modified version of
[Kubespray](https://github.com/kubernetes-sigs/kubespray) to run on
Sanger's infrastructure, from our sister team in [Cellular
Genetics](https://github.com/cellgeni). Their repo, itself a fork of
upstream Kubespray, is checked in here. HGI's implementation doesn't
necessarily follow best practices, in a software engineer or devops
sense, but it works. For now.

This documentation serves as a step-by-step guide, following that
provided by Cellgeni, to get everything up-and-running.

## Provisioning the Cluster

### Getting Started

You will need an OpenStack project/tenancy to deploy your cluster into.
For deployment, you will need a host that can speak to OpenStack, with
Terraform, Ansible and the OpenStack client installed. It's definitely
worth setting your environment up in a `tmux` session, to avoid having
to go through the rigmarole each time!

Clone this repository:

    git clone --recurse-submodule https://github.com/wtsi-hgi/hgi-k8s.git

The Cellgeni Kubespray module is set to track upstream master. If this
has become out-dated, it can be updated with:

    git submodule update --remote

The first thing you'll need to do is source `activate.rc`, which sets
the appropriate environment variables for communicating with our
OpenStack project. This works by retrieving HGI's secrets from GitLab,
provisioned by [`hgi-systems`](https://github.com/wtsi-hgi/hgi-systems).
For this to run successfully -- presuming `hgi-systems` is still a thing
-- the `GITLAB_URL` and `GITLAB_TOKEN` environment variables must be
set; these values can be found in the usual place.

Note that the automatic fetching of credentials is a nicety; they can be
hardcoded into `activate.rc` -- along with the other things that are
hardcoded and will need modifying if you're deploying into a different
OpenStack project -- providing they're not checked in!

*TODO* `activate.rc` also sources some Cellgeni dependencies that are
not currently checked in. This is mostly concerned with setting up and
initialising a Conda environment with the necessary bits-and-pieces to
setup K8s (specifically Terraform and Ansible).

If you don't have an `id_rsa` SSH key, you will also need to generate
one and add it to your SSH agent:

```bash
ssh-keygen -t rsa
eval $(ssh-agent -s)
ssh-add ~/.ssh/id_rsa
```

This could potentially be done differently, such that there is a special
K8s key. Currently, the K8s cluster is using `mercury`'s key.

### Deploying the Infrastructure

The Terraform inventories used to create the infrastructure in our
OpenStack project is defined in `inventory`. Specifically, for the `dev`
cluster, the configuration is defined in `inventory/dev/cluster.tf`.
The important settings here are the number and flavour of K8s master and
worker nodes, which ought to be set to fit into your OpenStack project's
quota.

Note that instance flavours are given by their ID, rather than their
name (e.g., `o1.medium`). These can be looked up with the OpenStack
client:

    openstack flavor list

Note that Kubespray uses etcd nodes; standalone and/or cohabiting the
K8s master nodes. etcd's consensus algorithm prefers an odd number of
etcd nodes and this is enforced in Kubespray's Ansible playbook;
therefore, ensure the number of these nodes is odd. Our development
cluster uses one master K8s node and no standalone; increasing the
number of K8s masters increases resilience, but this parity constraint
must be maintained.

Note that we have chosen to use a bastion node to route all traffic --
i.e., it gets a floating IP -- therefore all K8s master and worker nodes
are only available within the private network.

The other settings in the Terraform configuration are either
Sanger-specific (i.e., probably won't need changing) or aren't
used/artefacts from ~stealing~ lifting this from Cellgeni (e.g.,
GlusterFS).

First, to initialise Terraform, run the following from your cluster's
inventory directory:

    terraform init ../../cellgeni-kubespray/contrib/terraform/openstack

(As a convenience, you might want to symlink
`../../cellgeni-kubespray/contrib/terraform/openstack`, as you'll be
typing this a lot!)

Then, to create the cluster, run:

    terraform apply -var-file=cluster.tf ../../cellgeni-kubespray/contrib/terraform/openstack

Note that `provision.sh` notionally performs this operation, but is not
tested. It provides a useful reference in the meantime.

#### Destroying the Infrastructure

`terraform destroy` can be used to bring down the infrastructure, but
note that if you've configured any instances with Ansible, or run any
services in K8s, then you'll have to do some manual clean up first. If
you don't, OpenStack objects -- particularly networking components and
volumes -- can get orphaned, which then become very difficult to remove.

### Configuring the Infrastructure

Once Terraform has created its infrastructure, Ansible can be used to
configure the instances as a K8s cluster. We must first make some
changes to our cluster's inventory:

* We have observed that Terraform consistently wipes the contents of the
  `no-floating.yml` group variables, for your cluster's inventory. It
  doesn't delete the file, just empties the contents. It's weird. You
  will need to restore this with Git, say:

      git checkout -- inventory/dev/group_vars/no-floating.yml

* `no-floating.yml`, once restored, defines the SSH arguments that
  Ansible will use to route to the cluster nodes via the bastion host.
  The floating IP of the bastion host is hardcoded into this file and
  must be changed to the actual floating IP of the bastion host.

* The `all.yml` group variables will also need to be edited:
  * `openstack_lbaas_subnet_id` needs to be set to that logged in
    Terraform's state file (i.e., `terraform show terraform.tfstate | grep ' subnet_id'`)
  * `bin_dir` should be `/usr/local/bin`, if it's not already
  * `cloud_provider` should be `openstack`, if it's not already

* The `k8s-cluster.yml` group variables will also need to be edited:
  * `kube_network_plugin` should be `calico`, if it's not already
  * `resolvconf_mode` should be `docker_dns`, if it's not already

To use Calico networking, your OpenStack project's network's ports need
to be configured, where `$CLUSTER` is defined appropriately (e.g.,
`dev`):

```bash
join -t" " -o "1.2" \
     <(openstack port list -f value -c device_id -c id | sort) \
     <(openstack server list --name "${CLUSTER}-.*" -f value -c ID | sort) \
| xargs -n1 openstack port set --allowed_address ip-address=10.233.0.0/18 \
                               --allowed_address ip-address=10.233.64.0/18
```

Finally, before Ansible can be run, the `TERRAFORM_STATE_ROOT`
environment variable should be set to the cluster's inventory root, say:

```bash
export TERRAFORM_STATE_ROOT="$(pwd)/inventory/${CLUSTER}"
```

To test everything is working and that Ansible can contact all your
cluster's hosts, run the following from the `cellgeni-kubespray`
directory:

    ansible -i ../inventory/${CLUSTER}/hosts -m ping all

Providing all is well, the playbook can then be run to install K8s:

    ansible-playbook --become -i ../inventory/${CLUSTER}/hosts cluster.yml

This will take a bit of time...
