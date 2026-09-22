# Provider, lookups into the shared stack, and names used by every file of this stack.

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      project    = var.project
      owner      = var.owner
      env        = "lab"
      stack      = "cluster"
      managed-by = "terraform"
    }
  }
}

data "aws_caller_identity" "current" {}

# Zones that need no opt-in; two of them (design §3: 2 AZs).
data "aws_availability_zones" "available" {
  state = "available"
  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }
}

data "aws_route53_zone" "parent" {
  name         = "${var.parent_domain}."
  private_zone = false
}

# Read from the shared stack by NAME, never written (Terraform A2.4): the only way this stack can reach them is to
# read them, so `make down` has no path to deleting a secret. If `make shared` has not run, plan fails here.
data "aws_secretsmanager_secret" "this" {
  for_each = toset(["llm", "langfuse", "alerting", "wireguard"])
  name     = "${var.project}/${each.key}"
}

# Ubuntu 24.04 for the gateway, looked up at plan time instead of a hard-coded AMI id.
data "aws_ssm_parameter" "ubuntu_2404" {
  name = "/aws/service/canonical/ubuntu/server/24.04/stable/current/amd64/hvm/ebs-gp3/ami-id"
}

locals {
  name       = var.project
  account_id = data.aws_caller_identity.current.account_id
  domain     = "${var.project}.${var.parent_domain}"
  azs        = slice(data.aws_availability_zones.available.names, 0, 2)

  # Private subnets are /19 because the VPC CNI gives every pod a VPC address; public ones are small (/24): they
  # hold only the public ALB, the NAT gateway and the VPN gateway.
  private_subnets = [for i in range(2) : cidrsubnet(var.vpc_cidr, 3, i)]         # 10.30.0.0/19, 10.30.32.0/19
  public_subnets  = [for i in range(2) : cidrsubnet(var.vpc_cidr, 8, i + 200)]   # 10.30.200.0/24, 10.30.201.0/24
  # Two tiny subnets used ONLY by the EKS control-plane ENIs (the private endpoint). Keeping them apart is what lets the
  # VPN gateway drop tunnel traffic to the API server while still forwarding 443 to the internal ALB (wireguard-init.sh).
  control_plane_subnets = [for i in range(2) : cidrsubnet(var.vpc_cidr, 12, i + 4000)] # 10.30.250.0/28, 10.30.250.16/28
  control_plane_cidr    = cidrsubnet(var.vpc_cidr, 11, 2000)                            # 10.30.250.0/27, covers both

  # Only these three may be read by External Secrets — named, not `anime/*` (Terraform A5.4).
  external_secret_arns = [for k in ["llm", "langfuse", "alerting"] : data.aws_secretsmanager_secret.this[k].arn]
}
