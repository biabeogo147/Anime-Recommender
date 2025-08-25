#!/bin/bash

# Turn off swap memory for k8s to manage RAM correctly:
sudo swapoff -a
sudo sed -i '/swap.img/s/^/#/' /etc/fstab

# overlay: filesystem driver for containers to share layers.
# br_netfilter: bridge network filtering, required for Kubernetes networking.
# Enable kernel modules for containerd, ensure they load on boot:
echo -e "overlay\nbr_netfilter" | sudo tee /etc/modules-load.d/containerd.conf

# Load the modules now:
sudo modprobe overlay
sudo modprobe br_netfilter

# Set system configurations for Kubernetes networking:
echo "net.bridge.bridge-nf-call-ip6tables = 1" | sudo tee -a /etc/sysctl.d/kubernetes.conf
echo "net.bridge.bridge-nf-call-iptables = 1" | sudo tee -a /etc/sysctl.d/kubernetes.conf
echo "net.ipv4.ip_forward = 1" | sudo tee -a /etc/sysctl.d/kubernetes.conf

# Apply the new sysctl settings:
sudo sysctl --system

#Install Docker dependencies and set up the Docker repository:
sudo apt install -y curl gnupg2 software-properties-common apt-transport-https ca-certificates
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmour -o /etc/apt/trusted.gpg.d/docker.gpg
sudo add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"

# Install, Configure Containerd and restart the service:
sudo apt update -y
sudo apt install -y containerd.io
containerd config default | sudo tee /etc/containerd/config.toml >/dev/null 2>&1
sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/g' /etc/containerd/config.toml
sudo systemctl restart containerd
sudo systemctl enable containerd

# Set up the Kubernetes apt repository:
echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.30/deb/ /" | sudo tee /etc/apt/sources.list.d/kubernetes.list
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.30/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg

# Install kubeadm, kubelet and kubectl:
sudo apt update -y
sudo apt install -y kubelet kubeadm kubectl
sudo apt-mark hold kubelet kubeadm kubectl