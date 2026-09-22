#!/usr/bin/env bash
# cloud-init for the WireGuard gateway, rendered by Terraform's templatefile(): names written as dollar-brace are
# filled in by Terraform before boot; $NAME without braces are shell variables, left for bash.
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

# The Elastic IP replaces the temporary public address a few seconds after boot and drops open connections, so every
# network step is retried, and fails the script only after ten attempts.
retry() {
  for attempt in 1 2 3 4 5 6 7 8 9 10; do
    "$@" && return 0
    sleep 10
  done
  return 1
}

# unattended-upgrades holds the dpkg lock on first boot; wait for it inside apt instead of failing fast.
APT="apt-get -o DPkg::Lock::Timeout=600"
retry $APT update
retry $APT install -y wireguard-tools jq unzip iptables

# AWS CLI v2 from AWS itself (Ubuntu's awscli package is not v2).
cd /tmp
retry curl -fsSL -o awscliv2.zip https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip
unzip -q awscliv2.zip
./aws/install --update

# Keys come from the secret only this instance's role may read. umask 077: the temporary file is private.
umask 077
retry aws --region "${region}" secretsmanager get-secret-value \
  --secret-id "${secret_id}" --query SecretString --output text > /run/wireguard-secret.json
# Deliberately NOT retried: a secret missing a key is a setup error, and retrying would only hide it for 100 s.
jq -e '.serverPrivateKey and .operatorPublicKey' /run/wireguard-secret.json >/dev/null
PRIVATE_KEY=$(jq -r .serverPrivateKey /run/wireguard-secret.json)
PEER_KEY=$(jq -r .operatorPublicKey /run/wireguard-secret.json)
rm -f /run/wireguard-secret.json
INTERFACE=$(ip route show default | awk '{print $5; exit}')

# What the tunnel may reach: TCP 443 inside the VPC — the internal ALB — and nothing else. The API server also listens on
# 443 inside the VPC, so its subnets are dropped FIRST: kubectl goes through SSM from the workstation, never through the
# VPN (the endpoint name resolves publicly to private IPs, so without this rule a VPN laptop could reach it). Not the
# gateway itself either. Replies come back; nothing in the VPC can open a connection towards the laptop.
#
# MASQUERADE rewrites the source of tunnel traffic to the gateway's own VPC address. Without it the request reaches
# the internal ALB and the reply has no route back to 10.98.0.0/24 — "VPN on, the UI never loads" (GitOps A6.3). A
# consequence worth knowing: the ALB sees the gateway's VPC address, so its security-group rule for the VPC CIDR is
# the one that actually matches (GitOps A8.3).
cat > /etc/wireguard/wg0.conf <<EOF
[Interface]
Address = ${server_address}
ListenPort = 51820
PrivateKey = $PRIVATE_KEY
PostUp = iptables -N WG_FWD
PostUp = iptables -A WG_FWD -d ${control_plane} -j DROP
PostUp = iptables -A WG_FWD -d ${vpc_cidr} -p tcp --dport 443 -j ACCEPT
PostUp = iptables -A WG_FWD -j DROP
PostUp = iptables -A FORWARD -i wg0 -j WG_FWD
PostUp = iptables -A FORWARD -o wg0 -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
PostUp = iptables -A FORWARD -o wg0 -j DROP
PostUp = iptables -A INPUT -i wg0 -j DROP
PostUp = iptables -t nat -A POSTROUTING -s ${wireguard_cidr} -o $INTERFACE -j MASQUERADE
PostDown = iptables -t nat -D POSTROUTING -s ${wireguard_cidr} -o $INTERFACE -j MASQUERADE
PostDown = iptables -D INPUT -i wg0 -j DROP
PostDown = iptables -D FORWARD -o wg0 -j DROP
PostDown = iptables -D FORWARD -o wg0 -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
PostDown = iptables -D FORWARD -i wg0 -j WG_FWD
PostDown = iptables -F WG_FWD
PostDown = iptables -X WG_FWD

[Peer]
PublicKey = $PEER_KEY
AllowedIPs = ${peer_address}/32
EOF

chmod 600 /etc/wireguard/wg0.conf
# Without forwarding, packets from the tunnel are dropped at the gateway and never reach the VPC.
printf 'net.ipv4.ip_forward=1\n' > /etc/sysctl.d/99-wireguard.conf
sysctl --system
systemctl enable --now wg-quick@wg0
# The guide's readiness check looks for this file over SSM.
touch /var/log/wireguard-ready
