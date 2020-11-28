## setup kubernetees on baremetal ubuntu with systemd
## quoted from and edited:
## https://kubernetes.io/docs/setup/production-environment/container-runtimes/#containerd
## https://phoenixnap.com/kb/install-kubernetes-on-ubuntu


# ubuntu VM
# escalate privlege
```
sudo -i
sudo swapoff –a
# for the master node
sudo hostnamectl set-hostname master-node 

# for the worker node
sudo hostnamectl set-hostname worker01
```

# setup for containerd
```
cat <<EOF | sudo tee /etc/modules-load.d/containerd.conf
overlay
br_netfilter
EOF

sudo modprobe overlay
sudo modprobe br_netfilter

# Setup required sysctl params, these persist across reboots.
cat <<EOF | sudo tee /etc/sysctl.d/99-kubernetes-cri.conf
net.bridge.bridge-nf-call-iptables  = 1
net.ipv4.ip_forward                 = 1
net.bridge.bridge-nf-call-ip6tables = 1
EOF

# Apply sysctl params without reboot
sudo sysctl --system

```


# (Install containerd)
## Set up the repository
### Install packages to allow apt to use a repository over HTTPS
```
sudo apt-get update && sudo apt-get install -y apt-transport-https ca-certificates curl software-properties-common
```
## Add Docker's official GPG key
```
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key --keyring /etc/apt/trusted.gpg.d/docker.gpg add -
```
## Add Docker apt repository.
```
sudo add-apt-repository \
    "deb [arch=amd64] https://download.docker.com/linux/ubuntu \
    $(lsb_release -cs) \
    stable"
```

## Install containerd
```
sudo apt-get update && sudo apt-get install -y containerd.io
```

# Configure containerd

```
sudo mkdir -p /etc/containerd
sudo containerd config default > /etc/containerd/config.toml
```

# Restart containerd
```
sudo systemctl restart containerd
```

## To use the systemd cgroup driver in /etc/containerd/config.toml with runc, set
```
[plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runc]
  ...
  [plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runc.options]
    SystemdCgroup = true
```
```
sudo modprobe overlay
sudo modprobe br_netfilter
```
# Set up required sysctl params, these persist across reboots.
```
cat <<EOF | sudo tee /etc/sysctl.d/99-kubernetes-cri.conf
net.bridge.bridge-nf-call-iptables  = 1
net.ipv4.ip_forward                 = 1
net.bridge.bridge-nf-call-ip6tables = 1
EOF

sudo sysctl --system
```



```
VERSION=1.18
OS=xUbuntu_18.04

cat <<EOF | sudo tee /etc/apt/sources.list.d/devel:kubic:libcontainers:stable.list
deb http://download.opensuse.org/repositories/devel:/kubic:/libcontainers:/stable/$OS/ /
EOF
cat <<EOF | sudo tee /etc/apt/sources.list.d/devel:kubic:libcontainers:stable:cri-o:$VERSION.list
deb http://download.opensuse.org/repositories/devel:/kubic:/libcontainers:/stable:/cri-o:/$VERSION/$OS/ /
EOF

curl -L https://download.opensuse.org/repositories/devel:/kubic:/libcontainers:/stable/$OS/Release.key | sudo apt-key --keyring /etc/apt/trusted.gpg.d/libcontainers.gpg add -
curl -L https://download.opensuse.org/repositories/devel:kubic:libcontainers:stable:cri-o:$VERSION/$OS/Release.key | sudo apt-key --keyring /etc/apt/trusted.gpg.d/libcontainers-cri-o.gpg add -


sudo apt-get update
sudo apt-get install cri-o-1.16 cri-o-runc

```
## Start CRI-O:
```
sudo systemctl daemon-reload
sudo systemctl start crio
```
# (Install Docker CE)
## Set up the repository:
### Install packages to allow apt to use a repository over HTTPS
```
sudo apt-get update && sudo apt-get install -y \
  apt-transport-https ca-certificates curl software-properties-common gnupg2
```

# Add Docker's official GPG key:
```
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key --keyring /etc/apt/trusted.gpg.d/docker.gpg add -
```

# Add the Docker apt repository:
```
sudo add-apt-repository \
  "deb [arch=amd64] https://download.docker.com/linux/ubuntu \
  $(lsb_release -cs) \
  stable"
```

# Install Docker CE
```
# keep on mind the downgrade that we have setup already containerd
sudo apt-get update && sudo apt-get install containerd.io docker-ce docker-ce-cli
```

# Set up the Docker daemon
```
cat <<EOF | sudo tee /etc/docker/daemon.json
{
  "exec-opts": ["native.cgroupdriver=systemd"],
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "100m"
  },
  "storage-driver": "overlay2"
}
EOF
```

# Create /etc/systemd/system/docker.service.d
```
sudo mkdir -p /etc/systemd/system/docker.service.d
# debug
#cp -r /lib/systemd/system/docker.service /etc/systemd/system/docker.service.d
```
# Restart Docker
```
sudo systemctl daemon-reload
sudo systemctl restart docker
sudo systemctl enable docker
```

# install kubernetes




# initialize the control plane
```
sudo kubeadm init --pod-network-cidr=10.244.0.0/16

sudo kubeadm init --pod-network-cidr=10.244.0.0/16 --ignore-preflight-errors=all --v=5 --cri-socket /var/run/dockershim.sock

```
### Deploy Pod Network to Cluster
# A Pod Network is a way to allow communication between different nodes in the cluster. This tutorial uses the flannel virtual network.
# network containercreating stuck
## https://github.com/kubernetes/kubeadm/issues/1162#issuecomment-428158016
```
sudo kubectl apply -f https://raw.githubusercontent.com/coreos/flannel/master/Documentation/kube-flannel.yml

```

## Step 10: Join Worker Node to Cluster
```
kubeadm join --discovery-token abcdef.1234567890abcdef --discovery-token-ca-cert-hash sha256:1234..cdef 1.2.3.4:6443
```

# if you running sinle node
```
kubectl taint nodes --all node-role.kubernetes.io/master-
```

# setup firewall

```
master_node_ports = ('6443/tcp' '2379:2380/tcp' '10250/tcp' '10251/tcp' '10252/tcp' '10255/tcp')
worker_node_ports = ('10251/tcp' '10255/tcp')
for node in $selected_ufw_node
do
  sudo ufw allow node
done


```

