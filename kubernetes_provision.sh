#!/bin/bash
set -e

master_node_ports=('6443/tcp' '2379:2380/tcp' '10250/tcp' '10251/tcp' '10252/tcp' '10255/tcp' 'ssh')
worker_node_ports=('10251/tcp' '10255/tcp' 'ssh')

log_message(){
  if [ $? -eq 0 ]
  then
  printf "\e[0;32m \u2713 Success: $1 \e[0m \n"
  else
  printf "\e[0;31m \u2713 Failed: $1 \e[0m \n"
  fi
}

setup_firewall(){
  for port in ${SELECTED_UFW_NODE[@]}
  do
    sudo ufw allow $port
  done
  log_message "UFW setup for kubernetes network"
  sudo ufw enable
  log_message "UFW enabled"
  sudo ufw reload
  log_message "UFW reload"
}

request_node_hostname(){
    read -p "Enter node hostname: " node
    while [[ -z $node ]];do
        read -p "Enter node hostname: " node
    done
}
install_node_options(){
    echo "Choose node target mode"
    install_app_options=( "master" "worker" "quit")
    select opt in "${install_app_options[@]}"
    do
        case $opt in
        1|master)
          request_node_hostname
          export NODE_MODE=$node
          export SELECTED_UFW_NODE=${master_node_ports[@]}
        break
        ;;
        2|worker)
          request_node_hostname
          export NODE_MODE=$node
          export SELECTED_UFW_NODE=${worker_node_ports[@]}
        break
        ;;
        3|quit)
        exit
        break
        ;;
        *) echo "invalid option $REPLY";;

        esac
    done
}


setup_docker_systemd(){

cat <<EOF | sudo tee /etc/modules-load.d/containerd.conf > /dev/null 2>&1
overlay
br_netfilter
EOF
log_message "containerd config add"


sudo modprobe overlay > /dev/null 2>&1
sudo modprobe br_netfilter > /dev/null 2>&1
log_message "containerd config apply"

cat <<EOF | sudo tee /etc/sysctl.d/99-kubernetes-cri.conf > /dev/null 2>&1
net.bridge.bridge-nf-call-iptables  = 1
net.ipv4.ip_forward                 = 1
net.bridge.bridge-nf-call-ip6tables = 1
EOF

log_message "CRI conf add"
# refresh system without boot
sudo sysctl --system > /dev/null 2>&1
log_message "system reset"
# install supportive packages
sudo apt-get install -y apt-transport-https ca-certificates curl software-properties-common gnupg2 > /dev/null 2>&1
log_message "Install ca-certificates curl software-properties-common gnupg2"
# Add docker
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key --keyring /etc/apt/trusted.gpg.d/docker.gpg add - > /dev/null 2>&1
sudo add-apt-repository \
    "deb [arch=amd64] https://download.docker.com/linux/ubuntu \
    $(lsb_release -cs) \
    stable" > /dev/null 2>&1

log_message "Install docker"
# install containerd 
sudo apt-get update && sudo apt-get install -y containerd.io > /dev/null 2>&1
log_message "install containerd.io"

sudo mkdir -p /etc/containerd > /dev/null 2>&1
sudo containerd config default > /etc/containerd/config.toml
log_message "containered config copied to /etc/containerd/config.toml"

sudo systemctl restart containerd > /dev/null 2>&1
log_message "restart containerd"

sudo systemctl enable containerd > /dev/null 2>&1
log_message "enable containerd"
# ADDED CGROUPS TO /etc/containerd/config.toml
## To use the systemd cgroup driver in /etc/containerd/config.toml with runc, set

sed -i'' -e '/containerd.runtimes.runc\]/{
N;N;N;N;a\
        [plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runc.options]\
          SystemdCgroup = true
}' /etc/containerd/config.toml


# sudo nano /etc/containerd/config.toml
log_message '
Add the systemd cgroup driver in /etc/containerd/config.toml with runc
[plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runc]
  ...
  [plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runc.options]
    SystemdCgroup = true
'

sudo modprobe overlay > /dev/null 2>&1
sudo modprobe br_netfilter > /dev/null 2>&1
log_message "containerd config reapply"

cat <<EOF | sudo tee /etc/sysctl.d/99-kubernetes-cri.conf > /dev/null 2>&1
net.bridge.bridge-nf-call-iptables  = 1
net.ipv4.ip_forward                 = 1
net.bridge.bridge-nf-call-ip6tables = 1
EOF
log_message "Add CRI cof to /etc/sysctl.d/99-kubernetes-cri.conf"

sudo sysctl --system > /dev/null 2>&1
log_message "system reset"

#cri version
VERSION=1.18
OS=xUbuntu_18.04

cat <<EOF | sudo tee /etc/apt/sources.list.d/devel:kubic:libcontainers:stable.list > /dev/null 2>&1
deb http://download.opensuse.org/repositories/devel:/kubic:/libcontainers:/stable/$OS/ /
EOF
log_message "add kubectl to apt repo"

cat <<EOF | sudo tee /etc/apt/sources.list.d/devel:kubic:libcontainers:stable:cri-o:$VERSION.list > /dev/null 2>&1
deb http://download.opensuse.org/repositories/devel:/kubic:/libcontainers:/stable:/cri-o:/$VERSION/$OS/ /
EOF
log_message "add cri to apt repo"

curl -L https://download.opensuse.org/repositories/devel:/kubic:/libcontainers:/stable/$OS/Release.key | sudo apt-key --keyring /etc/apt/trusted.gpg.d/libcontainers.gpg add - > /dev/null 2>&1
log_message "download kube"

wait $!

curl -L https://download.opensuse.org/repositories/devel:kubic:libcontainers:stable:cri-o:$VERSION/$OS/Release.key | sudo apt-key --keyring /etc/apt/trusted.gpg.d/libcontainers-cri-o.gpg add - > /dev/null 2>&1
log_message "download cri"

sudo apt-get update > /dev/null 2>&1
log_message "system update"

sudo apt-get install -y cri-o-1.16 cri-o-runc
log_message "Install cri-o and cri-o-runc"

sudo systemctl daemon-reload > /dev/null 2>&1
log_message "system daemon reload"

sudo systemctl start crio > /dev/null 2>&1
log_message "start crio"

sudo systemctl enable crio > /dev/null 2>&1
log_message "enable crio"

curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key --keyring /etc/apt/trusted.gpg.d/docker.gpg add - > /dev/null 2>&1
log_message "add docker apt keys"
sudo add-apt-repository \
  "deb [arch=amd64] https://download.docker.com/linux/ubuntu \
  $(lsb_release -cs) \
  stable" > /dev/null 2>&1

log_message "download kubernetes"

sudo apt-get update && sudo apt-get -y install docker-ce docker-ce-cli > /dev/null 2>&1
log_message "install docker-ce docker-ce-cli"

cat <<EOF | sudo tee /etc/docker/daemon.json > /dev/null 2>&1
{
  "exec-opts": ["native.cgroupdriver=systemd"],
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "100m"
  },
  "storage-driver": "overlay2"
}
EOF
log_message "docker conf add to  /etc/docker/daemon.json"

sudo mkdir -p /etc/systemd/system/docker.service.d > /dev/null 2>&1
log_message "dir create /etc/systemd/system/docker.service.d"

cp -r /lib/systemd/system/docker.service /etc/systemd/system/docker.service.d > /dev/null 2>&1
log_message "docker conf copy from /lib/systemd/system/docker.service"

sudo systemctl daemon-reload > /dev/null 2>&1
log_message "system daemon reload"

sudo systemctl restart docker > /dev/null 2>&1
log_message "docker restart"

sudo systemctl enable docker > /dev/null 2>&1
log_message "docker enable"


}

setup_kubernetes(){
sudo apt-get update > /dev/null 2>&1
log_message "System update"

sudo swapoff --all
log_message "Swap off"
sudo sed -i '/ swap / s/^/#/' /etc/fstab
log_message "Swap off persisted"

#sudo hostnamectl set-hostname master-node > /dev/null 2&>1
sudo hostnamectl set-hostname $NODE_MODE
log_message "set hostname $NODE_MODE"

# INSTALL KUBERNETES
curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo apt-key add > /dev/null 2>&1
log_message "add kubernetes apt key"

sudo apt-add-repository "deb http://apt.kubernetes.io/ kubernetes-xenial main" > /dev/null 2>&1
log_message "add kubernetes repo"

sudo apt-get install -y kubeadm kubelet kubectl > /dev/null 2>&1
log_message "download kubeadm kubelet kubectl"

sudo apt-mark hold kubeadm kubelet kubectl > /dev/null 2>&1
log_message "hold updates kubeadm kubelet kubectl"

}


init(){
  echo -e "\e[106m this kubernetes metal server setup script is designed for Ubuntu_18.04 VM that runs with systemd \e[0m"
  echo -e "\e[208m IT MUST RUN WITH SUDO PRIVILGES \e[0m"
  echo -e "\e[1;35m *** if you are not in root mode please exit and run [sudo -i] first *** \e[0m"

  install_node_options
  wait $!
  setup_docker_systemd
  setup_kubernetes
  setup_firewall
}

init

echo -e " \e[44m  ALL GOOD \e[0m
  TO initialize a cluster plane NOW RUN:\n
    \e[38;5;44m $ sudo kubeadm init --pod-network-cidr=10.244.0.0/16 --ignore-preflight-errors=all --v=5 --cri-socket /var/run/dockershim.sock \e[0m \n
  THEN INSTALL NETWROKING FLANNEL:\n
    \e[38;5;44m  $ sudo kubectl apply -f https://raw.githubusercontent.com/coreos/flannel/master/Documentation/kube-flannel.yml \e[0m  \n
  IF YOU WANT TO JOIN YOUR WORKER NODES:\n
   \e[38;5;44m  $ kubeadm join --discovery-token .... --discovery-token-ca-cert-hash ... \e[0m 
"
