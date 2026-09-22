# The VPC: two zones, private subnets for nodes and the internal ALB, public ones for the public ALB, the NAT
# gateway and the VPN gateway.
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 6.0"

  name = local.name
  cidr = var.vpc_cidr
  azs  = local.azs

  private_subnets = local.private_subnets
  public_subnets  = local.public_subnets
  intra_subnets   = local.control_plane_subnets # no route to the internet; only the API server's ENIs live here

  # ONE NAT gateway for both zones: cheaper, and a single point of failure for everything pods reach outside the
  # VPC — Gemini, Hugging Face, Langfuse, Discord. Accepted and recorded (Terraform A8.3, design §10).
  enable_nat_gateway = true
  single_nat_gateway = true

  # The EKS private endpoint is a hostname answered by an AWS-managed private zone. Both flags must be on, or the
  # gateway's SSM agent cannot resolve it and `make tunnel` fails with a DNS error (design §4.7).
  enable_dns_support   = true
  enable_dns_hostnames = true

  map_public_ip_on_launch = false # nothing gets a public address by sitting in a public subnet

  # How the load balancer controller finds subnets. Without the first tag the public ALB is never created; without
  # the second the internal one is never created — and each fails without touching the other, which reads like
  # an Ingress problem rather than a network one (GitOps A3.9).
  public_subnet_tags  = { "kubernetes.io/role/elb" = "1" }
  private_subnet_tags = { "kubernetes.io/role/internal-elb" = "1" }
}

output "vpc_id" {
  value = module.vpc.vpc_id
}
