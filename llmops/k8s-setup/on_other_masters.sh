#!/bin/bash

# Get token and sha from the output of the first master node setup (on_first_master.sh)
sudo kubeadm join 192.168.0.200:6443 --token your_token \
  --discovery-token-ca-cert-hash your_sha \
  --control-plane \
  --certificate-key your_cert
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config
