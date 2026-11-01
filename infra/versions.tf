terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }

  # Values come from backend.hcl so the bucket name is not hardcoded:
  #   terraform init -backend-config=backend.hcl
  backend "s3" {}
}

provider "aws" {
  region  = var.region
  profile = var.aws_profile

  # Every resource gets these tags, which makes the billing console
  # easy to filter and proves nothing is left running.
  default_tags {
    tags = {
      Project   = var.project
      ManagedBy = "terraform"
    }
  }
}
