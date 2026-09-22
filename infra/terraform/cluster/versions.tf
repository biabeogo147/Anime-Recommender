# Terraform and provider versions for the `cluster` stack — everything `make down` destroys every night.
terraform {
  required_version = ">= 1.11"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }

  # Same bucket as the shared stack, its own key. Bucket name passed by `make` with -backend-config.
  backend "s3" {
    key          = "anime/cluster/terraform.tfstate"
    use_lockfile = true
    encrypt      = true
  }
}
