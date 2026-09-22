# Terraform and provider versions for the `shared` stack — the one `make down` never touches.
terraform {
  # 1.11 is the first release where the S3 backend's own lockfile (use_lockfile) is generally available,
  # which is what replaces a DynamoDB lock table here. The ops workstation runs 1.16.
  required_version = ">= 1.11"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0" # any 6.x; a 7.0 could change resource schemas under us
    }
  }

  # State lives in Medical's existing bucket, under an `anime/` prefix, so this project needs no bucket and
  # no lock table of its own. A backend block cannot read variables, so the bucket name (it contains the
  # account id) is passed by `make` with -backend-config and never written into Git.
  backend "s3" {
    key          = "anime/shared/terraform.tfstate"
    use_lockfile = true # a .tflock object next to the state stops two applies running at once
    encrypt      = true
  }
}
