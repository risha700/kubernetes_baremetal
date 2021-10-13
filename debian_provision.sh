#!/bin/bash
# set -e

master_node_ports=('6443/tcp' '2379:2380/tcp' '10250/tcp' '10251/tcp' '10252/tcp' '10255/tcp' 'ssh')
worker_node_ports=('10250/tcp' '10251/tcp' '10255/tcp' 'ssh')

log_message(){
  if [[ $? -eq 0 ]];then
    printf "\e[0;32m \u2713 Success: $1 \e[0m \n"
  else
    printf "\e[0;31m \u2713 Failed: $1 \e[0m \n"
    exit 1
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


# #=========================> prepare docker
log_message "|=============installing packages================|"
sudo apt install apt-transport-https ca-certificates curl software-properties-common gnupg2 ufw -y > /dev/null 2>&1
log_message "Install ca-certificates curl software-properties-common gnupg2 ufw"
# # # Add docker
# # curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key --keyring /etc/apt/trusted.gpg.d/docker.gpg add - > /dev/null 2>&1
# # sudo add-apt-repository \
# #     "deb [arch=amd64] https://download.docker.com/linux/ubuntu \
# #     $(lsb_release -cs) \
# #     stable" -y > /dev/null 2>&1

# # log_message "Install docker"
# install containerd 
#=========================> prepare containerd
log_message "|=============preparing containerd environment=================|"
cat <<EOF | sudo tee /etc/modules-load.d/containerd.conf > /dev/null 2>&1
overlay
br_netfilter
EOF
log_message "containerd config added to /etc/modules-load.d/containerd.conf"
sudo modprobe overlay > /dev/null 2>&1
sudo modprobe br_netfilter > /dev/null 2>&1
log_message "containerd config applied modprobe"

cat <<EOF | sudo tee /etc/sysctl.d/99-kubernetes-cri.conf > /dev/null 2>&1
net.bridge.bridge-nf-call-iptables  = 1
net.ipv4.ip_forward                 = 1
net.bridge.bridge-nf-call-ip6tables = 1
EOF
log_message "containerd params persist config in /etc/sysctl.d/99-kubernetes-cri.conf"

sudo apt update && sudo apt install containerd -y > /dev/null 2>&1
log_message "install containerd.io"

sudo mkdir -p /etc/containerd > /dev/null 2>&1
sudo containerd config default > /etc/containerd/config.toml
log_message "containered config copied to /etc/containerd/config.toml"
sed -i -e 's/SystemdCgroup.*/SystemdCgroup=true/' /etc/containerd/config.toml
log_message ' changed SystemdCgroup = true to  /etc/containerd/config.toml with runc'

sudo systemctl restart containerd > /dev/null 2>&1
log_message "restart containerd"

sudo systemctl enable containerd > /dev/null 2>&1
log_message "enable containerd"

sudo sysctl --system > /dev/null 2>&1
log_message "system reset"

#cri version
VERSION=1.22
OS=Debian_11

cat <<EOF | sudo tee /etc/apt/sources.list.d/devel:kubic:libcontainers:stable.list > /dev/null 2>&1
deb http://download.opensuse.org/repositories/devel:/kubic:/libcontainers:/stable/$OS/ /
EOF
log_message "add kubectl to apt repo"
log_message "downloading kube"
curl -L https://download.opensuse.org/repositories/devel:/kubic:/libcontainers:/stable/$OS/Release.key | sudo apt-key --keyring /etc/apt/trusted.gpg.d/libcontainers.gpg add - > /dev/null 2>&1
log_message "kube download"

wait $!
log_message "upgrading packages..."
sudo apt update && sudo apt upgrade -y > /dev/null 2>&1
log_message "system updated"
sudo systemctl daemon-reload > /dev/null 2>&1
log_message "system daemon reload"

curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key --keyring /etc/apt/trusted.gpg.d/docker.gpg add - > /dev/null 2>&1
log_message "added docker apt keys"
sudo add-apt-repository \
  "deb [arch=amd64] https://download.docker.com/linux/debian \
  $(lsb_release -cs) stable" -y > /dev/null 2>&1

log_message "downloading docker..."
sudo apt update && sudo apt install docker-ce docker-ce-cli -y > /dev/null 2>&1
log_message "install docker-ce docker-ce-cli"

sudo cat <<EOF | sudo tee /etc/docker/daemon.json > /dev/null 2>&1
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

sudo cp -r /lib/systemd/system/docker.service /etc/systemd/system/docker.service.d > /dev/null 2>&1
log_message "docker conf copy from /lib/systemd/system/docker.service"

sudo systemctl daemon-reload > /dev/null 2>&1
log_message "system daemon reload"

sudo systemctl restart docker > /dev/null 2>&1
log_message "docker restart"

sudo systemctl enable docker > /dev/null 2>&1
log_message "docker enable"


}

setup_kubernetes(){
log_message "|=============preparing kubernetes environment=================|"

sudo apt update && sudo apt upgrade -y > /dev/null 2>&1
log_message "System updated"

sudo swapoff --all
log_message "Swap off"
sudo sed -i '/ swap / s/^/#/' /etc/fstab
log_message "Swap off persisted"

#sudo hostnamectl set-hostname master-node > /dev/null 2&>1
sudo hostnamectl set-hostname $NODE_MODE
log_message "set hostname $NODE_MODE"

cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
br_netfilter
EOF

cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
EOF
sudo sysctl --system
log_message "iptables set bridge traffic"


# INSTALL KUBERNETES
sudo curl -fsSLo /usr/share/keyrings/kubernetes-archive-keyring.gpg https://packages.cloud.google.com/apt/doc/apt-key.gpg
# curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo apt-key add > /dev/null 2>&1
log_message "add kubernetes apt key"
echo "deb [signed-by=/usr/share/keyrings/kubernetes-archive-keyring.gpg] https://apt.kubernetes.io/ kubernetes-xenial main" | sudo tee /etc/apt/sources.list.d/kubernetes.list
# sudo apt-add-repository "deb http://apt.kubernetes.io/ kubernetes-xenial main" -y > /dev/null 2>&1
log_message "add kubernetes repo"

sudo apt install kubeadm kubelet kubectl -y > /dev/null 2>&1
sudo apt-get update
sudo apt-get install -y kubelet kubeadm kubectl
log_message "download kubeadm kubelet kubectl"
sudo apt-mark hold kubelet kubeadm kubectl
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
    \e[38;5;44m 
    # keep on mind 
    CALICO --pod-network-cidr=192.168.0.0/16
    FLANNEL --pod-network-cidr=10.244.0.0/16
    $ sudo kubeadm init --pod-network-cidr=192.168.0.0/16 --ignore-preflight-errors=all --v=5 --cri-socket /var/run/dockershim.sock \
    --apiserver-advertise-address=master-machine-ip
    
    \e[0m \n
  THEN INSTALL NETWROKING FLANNEL :\n
    \e[38;5;44m  $ sudo kubectl apply -f https://raw.githubusercontent.com/coreos/flannel/master/Documentation/kube-flannel.yml \e[0m  \n
  OR CALICO:\n
    \e[38;5;44m  
    # one liner
    $ sudo kubectl apply -f https://docs.projectcalico.org/v3.14/manifests/calico.yaml   \n
    # or docs version
    $ sudo kubectl create -f https://docs.projectcalico.org/manifests/tigera-operator.yaml \n
    $ sudo kubectl create -f https://docs.projectcalico.org/manifests/custom-resources.yaml \n
    \e[0m
  IF YOU WANT TO JOIN YOUR WORKER NODES:\n
   \e[38;5;44m  $ kubeadm join --discovery-token .... --discovery-token-ca-cert-hash ... \e[0m 
"
