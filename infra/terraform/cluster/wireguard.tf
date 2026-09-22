# The one machine this project owns inside the VPC. It does two jobs (Terraform A3.3):
#   1. WireGuard VPN — puts the operator's laptop inside the VPC so the internal ALB (the four admin UIs) is reachable;
#   2. SSM target for `make tunnel` — its SSM agent forwards the workstation's 127.0.0.1:6443 to the private EKS
#      endpoint.
# It lives in this stack, so `make down` destroys it, and a rebuild gives it a new Elastic IP; the client profile
# names it as vpn.anime, so only the record moves (Terraform A8.2).

resource "aws_iam_role" "wireguard" {
  name = "${local.name}-wireguard"
  assume_role_policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [{ Effect = "Allow", Action = "sts:AssumeRole", Principal = { Service = "ec2.amazonaws.com" } }]
  })
}

# Session Manager: the tunnel and, when needed, a shell — with no SSH key and no inbound port.
resource "aws_iam_role_policy_attachment" "wireguard_ssm" {
  role       = aws_iam_role.wireguard.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# Its own keys, and nothing else. This is the ONLY identity that can read anime/wireguard: not the nodes, not any pod.
resource "aws_iam_role_policy" "wireguard_secret" {
  name = "read-own-wireguard-secret"
  role = aws_iam_role.wireguard.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["secretsmanager:GetSecretValue", "secretsmanager:DescribeSecret"]
      Resource = data.aws_secretsmanager_secret.this["wireguard"].arn
    }]
  })
}

resource "aws_iam_instance_profile" "wireguard" {
  name = "${local.name}-wireguard"
  role = aws_iam_role.wireguard.name
}

resource "aws_security_group" "wireguard" {
  name        = "${local.name}-wireguard"
  description = "WireGuard gateway and SSM tunnel target; no SSH"
  vpc_id      = module.vpc.vpc_id
}

# The only inbound rule: the WireGuard handshake. Packets that do not authenticate are dropped without a reply, so a
# port scan sees nothing.
resource "aws_vpc_security_group_ingress_rule" "wireguard_udp" {
  security_group_id = aws_security_group.wireguard.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "udp"
  from_port         = 51820
  to_port           = 51820
  description       = "WireGuard; unauthenticated packets are discarded"
}

# Out: SSM and Secrets Manager endpoints, the EKS private endpoint, and the internal ALB for VPN traffic.
resource "aws_vpc_security_group_egress_rule" "wireguard_all" {
  security_group_id = aws_security_group.wireguard.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
  description       = "SSM, Secrets Manager, EKS endpoint, internal ALB"
}

resource "aws_instance" "wireguard" {
  ami                    = data.aws_ssm_parameter.ubuntu_2404.insecure_value # Ubuntu ships the SSM agent (snap)
  instance_type          = var.wireguard_instance_type
  subnet_id              = module.vpc.public_subnets[0]
  vpc_security_group_ids = [aws_security_group.wireguard.id]
  iam_instance_profile   = aws_iam_instance_profile.wireguard.name

  # A temporary public address so cloud-init can download packages at once; the Elastic IP replaces it seconds later,
  # which drops open connections — so every network step in the script retries.
  associate_public_ip_address = true

  user_data = templatefile("${path.module}/wireguard-init.sh", {
    region         = var.region
    secret_id      = data.aws_secretsmanager_secret.this["wireguard"].name
    server_address = "${cidrhost(var.wireguard_cidr, 1)}/${split("/", var.wireguard_cidr)[1]}" # 10.98.0.1/24
    peer_address   = cidrhost(var.wireguard_cidr, 2)                                          # 10.98.0.2
    wireguard_cidr = var.wireguard_cidr
    vpc_cidr       = var.vpc_cidr
    control_plane  = local.control_plane_cidr
  })
  # cloud-init runs the script on first boot only; a changed script must replace the instance to take effect.
  user_data_replace_on_change = true

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  root_block_device {
    volume_size = 8
    volume_type = "gp3"
    encrypted   = true
  }

  tags = { Name = "${local.name}-wireguard" }

  lifecycle {
    ignore_changes = [ami] # a new Ubuntu build must not replace the gateway mid-session
  }
}

resource "aws_eip" "wireguard" {
  domain   = "vpc"
  instance = aws_instance.wireguard.id
  tags     = { Name = "${local.name}-wireguard" }
}

# The ONLY record Terraform writes for Anime: the VPN endpoint. The six load-balancer names are written by
# external-dns, because their targets are created later by a controller Terraform never sees (design §3).
resource "aws_route53_record" "vpn" {
  zone_id = data.aws_route53_zone.parent.zone_id
  name    = "vpn.${local.domain}"
  type    = "A"
  ttl     = 60 # short, so a laptop that cached the old address after a rebuild recovers within a minute
  records = [aws_eip.wireguard.public_ip]
}

output "wireguard_instance_id" {
  value = aws_instance.wireguard.id
}

output "vpn_endpoint" {
  value = "${aws_route53_record.vpn.fqdn}:51820"
}

output "wireguard_client_address" {
  value = "${cidrhost(var.wireguard_cidr, 2)}/32"
}

output "vpc_cidr" {
  value = var.vpc_cidr
}
