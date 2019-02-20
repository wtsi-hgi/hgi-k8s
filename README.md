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
join -t" " -o "1.2" <(openstack port list -f value -c device_id -c id | sort) \
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

## Accessing Kubernetes

To access and administer K8s from your machine, you will need to
[install `kubectl`](https://kubernetes.io/docs/tasks/tools/install-kubectl/)
and set up networking and SSH on your local machine.

* Copy the K8s cluster's SSH key to your local machine and `chmod` it
  appropriately:

  ```bash
  scp user@host:/path/to/k8s/ssh/key ~/.ssh/k8s.key
  chmod 600 ~/.ssh/k8s.key
  ```

* Create a K8s SSH configuration file and `include` it in your master
  SSH configuration:

  ```ssh
  Host 10.0.0.*
    ProxyCommand ssh -W %h:%p k8s-bastion
    User ubuntu
    IdentityFile ~/.ssh/k8s.key
    ForwardX11 yes
    ForwardAgent yes
    ForwardX11Trusted yes

  Host k8s-bastion
    Hostname BASTION_IP
    User ubuntu
    IdentityFile ~/.ssh/k8s.key
    ForwardX11 yes
    ForwardAgent yes
    ForwardX11Trusted yes

  Host k8s-master
    Hostname MASTER_IP
    ProxyCommand ssh -W %h:%p k8s-bastion
    User ubuntu
    IdentityFile ~/.ssh/k8s.key

  Host k8s-tunnel
    Hostname BASTION_IP
    LocalForward 16443 MASTER_IP:6443
    IdentityFile ~/.ssh/k8s.key
    ServerAliveInterval 5
    ServerAliveCountMax 1
    User ubuntu
  ```

  Where `BASTION_IP` is the floating IP address of your bastion host and
  `MASTER_IP` is the IP address of any K8s master node within your
  subnet.

* Add a route to your K8s subnet via the bastion host, from your local
  machine. For example, on macOS:

  ```bash
  sudo route add -net 10.0.0.0/24 ${BASTION_IP}
  ```

  *Note: You probably won't need to do this. This step is included for
  completeness' sake.*

* Get K8s certificates and keys:

  ```bash
  # List keys
  ssh k8s-master sudo ls /etc/kubernetes/ssl

  # Get admin keys; change remote filename appropriately
  ssh k8s-master sudo cat /etc/kubernetes/ssl/admin-kube-master-1-key.pem > admin-key.pem
  ssh k8s-master sudo cat /etc/kubernetes/ssl/admin-kube-master-1.pem > admin.pem
  ssh k8s-master sudo cat /etc/kubernetes/ssl/ca.pem > ca.pem
  ```

* Configure `kubectl`:

  ```bash
  kubectl config set-cluster default-cluster --server=https://127.0.0.1:16443 --certificate-authority=ca.pem
  kubectl config set-credentials default-admin --certificate-authority=ca.pem --client-key=admin-key.pem --client-certificate=admin.pem
  kubectl config set-context default-system --cluster=default-cluster --user=default-admin
  kubectl config use-context default-system
  ```

  Ensure that `clusters.cluster.server`, in `~/.kube/config`, points to
  `https://127.0.0.1:16443`, so it can be accessed via an SSH tunnel.

* Start the SSH tunnel:

  ```bash
  ssh -fN k8s-tunnel
  ```

  You may need to kick this periodically.

`kubectl` should now be operational. In future, only the SSH tunnel will
need to be started to use `kubectl`.

### Using the Kubernetes Dashboard

Providing the SSH tunnel from the previous section is open, we can also
use the K8s dashboard, using:

    kubectl proxy

Which starts a proxy to the dashboard at
http://localhost:8001/api/v1/namespaces/kube-system/services/https:kubernetes-dashboard:/proxy/

However, to be able to use this, you will first need to create an admin
user and acquire an access token, by following [these
instructions](https://github.com/kubernetes/dashboard/wiki/Creating-sample-user).

See also: [Kubernetes Dashboard Overview](https://kubernetes.io/docs/tasks/access-application-cluster/web-ui-dashboard/#accessing-the-dashboard-ui)

## Deploying Services

### JupyterHub

Our JupyterHub is deployed via [Helm](https://helm.sh) using the [Zero
to JupyterHub](https://zero-to-jupyterhub.readthedocs.io/en/stable/)
chart. The aforementioned website gives a complete overview of how to
install and configure JupyterHub; herein follows a summary.

* Install Helm on a machine that can access the K8s cluster (e.g., the
  same one you installed `kubectl` on to). For example, on macOS, you
  can use Homebrew:

  ```bash
  brew install kubernetes-helm
  ```

* Install Helm on to the K8s cluster:

  ```bash
  kubectl --namespace kube-system create serviceaccount tiller
  kubectl create clusterrolebinding tiller-cluster-rule --clusterrole=cluster-admin --serviceaccount=kube-system:tiller
  helm init --service-account tiller
  kubectl patch deploy --namespace kube-system tiller-deploy -p '{"spec":{"template":{"spec":{"serviceAccount":"tiller"}}}}'
  ```

  Note that if Helm is already installed on the cluster, you will just
  need to run `helm init --client-only` on the client machine.

* Add JupyterHub to Helm:

  ```bash
  helm repo add jupyterhub https://jupyterhub.github.io/helm-chart/
  helm repo update
  ```

* JupyterHub needs its own persistent storage, to manage its state. To
  this end, we create a new cinder storage class, per the definition in
  Cellgeni's Kubespray repo:

  ```bash
  kubectl create -f cellgeni-kubespray/sanger/storage/sc-rw-once.yaml
  ```

* Start or upgrade JupyterHub, in the `jpt` namespace, with the
  following:

  ```bash
  helm upgrade --install jpt jupyterhub/jupyterhub --namespace jpt --version 0.7.0 --values jupyter/jupyter-config.yaml
  ```

The configuration in `jupyter/jupyter-config` defines, amongst other
things (see the aforementioned documentation for details):

* Authentication: We have chosen to use LDAP authentication. Note that,
  in spite of the documentation, a number of fields must be explicitly
  set for the service to start. Specifically:

  * `ldap.server.address`
  * `ldap.server.port`
  * `ldap.server.ssl`
  * `ldap.dn.lookup`
  * `ldap.dn.user.escape`
  * `ldap.dn.user.validRegex`
  * `ldap.dn.templates`

  This
  [mapping](https://github.com/jupyterhub/zero-to-jupyterhub-k8s/blob/a6824b7db1e4c42d7944f08510b7b1ac18b6de1a/images/hub/jupyterhub_config.py#L305-L318)
  of these values to the [underlying authentication
  module](https://github.com/jupyterhub/ldapauthenticator) is used, for
  future reference.

* Notebook Image: We have chosen to use our own notebook image, which is
  derived from the official Docker image stacks for SciPy and R. The
  repo for this can be found on GitHub as
  [`hgi-jupyter-notebook`](https://github.com/wtsi-hgi/hgi-jupyter-notebook)
  and is available for deployment from [Docker
  Hub](https://hub.docker.com/r/mercury/hgi-jupyter-notebook).

  This provides, as of writing, Python 3.6 and R 3.5 kernels, as well as
  common packages. This image will probably develop with time to suite
  our users' needs.

* Resources:

  * `singleuser.storage.capacity`, which defines the size of the
    persistent volume claim used by each users' pod;
  * `singleuser.memory.{limit,guarantee}`, which define the available
    memory to each users' pod;
  * `singleuser.cpu.{limit,guarantee}`, which define the available
    compute to each users' pod.

  We can use these values to easily calculate the maximum capacity of
  our cluster, in terms of concurrent users, by dividing them into the
  respective resources provided by the K8s worker nodes. The maximum
  capacity, in terms of total users, can likewise be found by dividing
  the total cluster volume quota by the prescribed PVC size.

When JupyterHub starts, it initiates a `proxy-public` service in the
`jpt` namespace, in K8s. This is provisioned with a floating IP, for
external endpoints, and allows access to the service over HTTP.

## To Do...

* [ ] Ingress controller, with TLS
* [ ] DNS setup (A record)
* [ ] Firewall setup, to allow access through VPN
* [ ] Internal network name resolution within K8s pods
* [ ] Reverse proxy K8s dashboard for convenience? (n.b., Security risk)
* [ ] Move to vanilla Kubespray and patch as neccessary, to make
      upstream updates easier to manage
