#!/bin/bash

sudo mkfs.ext4 -m 0 /dev/sdb
mkdir /data
echo "/dev/sdb  /data  ext4  defaults  0  0" | sudo tee -a /etc/fstab
mount -a
sudo df -h

mkdir /data/rancher
cd /data/rancher
echo
> docker-compose.yml
docker logs rancher-server 2>&1 | grep "Bootstrap Password:"