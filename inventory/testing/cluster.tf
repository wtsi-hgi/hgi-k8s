# your Kubernetes cluster name here
cluster_name = "testing"

# SSH key to use for access to nodes
public_key_path = "~/.ssh/id_rsa.pub"

# image to use for bastion, masters, standalone etcd instances, and nodes
image = "xenial-isg-docker-c52f7acc02b0c11d41b174707e4c271b16f52996"
# user on the node (ex. core on Container Linux, ubuntu on Ubuntu, etc.)
ssh_user = "ubuntu"

# 0|1 bastion nodes
number_of_bastions = 1
flavor_bastion = "8003" # o1.large

# standalone etcds
number_of_etcd = 0

# masters
number_of_k8s_masters = 0
number_of_k8s_masters_no_etcd = 0
number_of_k8s_masters_no_floating_ip = 3
number_of_k8s_masters_no_floating_ip_no_etcd = 0
flavor_k8s_master = "8003" # o1.large

# nodes
number_of_k8s_nodes = 0
number_of_k8s_nodes_no_floating_ip = 4
flavor_k8s_node = "2002" # m1.medium

# GlusterFS
# either 0 or more than one
number_of_gfs_nodes_no_floating_ip = 2
gfs_volume_size_in_gb = 500
# Container Linux does not support GlusterFS
image_gfs = "xenial-isg-docker-c52f7acc02b0c11d41b174707e4c271b16f52996"
# May be different from other nodes
ssh_user_gfs = "ubuntu"
flavor_gfs_node = "8002" # o1.medium

# networking
network_name = "testing"
external_net = "bfd77d25-d230-436a-a85a-b28b3dbdb814"
dns_nameservers=["172.18.255.1"]
floatingip_pool = "public"

