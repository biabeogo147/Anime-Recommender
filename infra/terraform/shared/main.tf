# Provider, shared lookups and names for the shared stack.

provider "aws" {
  region = var.region # no credentials here: Terraform uses the ops workstation's instance role

  # Added to every resource. The budget counts only resources tagged project=anime, so Medical's spend in the
  # same account never triggers Anime's alarms (and the reverse).
  default_tags {
    tags = {
      project    = var.project
      owner      = var.owner
      env        = "lab"
      stack      = "shared"
      managed-by = "terraform"
    }
  }
}

data "aws_caller_identity" "current" {}

# Medical's public zone. Read, never managed: destroying this stack must not be able to touch it.
data "aws_route53_zone" "parent" {
  name         = "${var.parent_domain}."
  private_zone = false
}

locals {
  account_id = data.aws_caller_identity.current.account_id
  # Every Anime name lives under this label, which is also the boundary external-dns is confined to.
  domain = "${var.project}.${var.parent_domain}" # anime.recruitai.io.vn
}
