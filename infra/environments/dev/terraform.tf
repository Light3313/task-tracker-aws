terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.53.0"
    }
  }

  required_version = ">=  1.15"

  backend "s3" {
    bucket       = "tt-tfstate-486949319589"
    key          = "task-tracker/dev/terraform.tfstate"
    region       = "us-east-1"
    use_lockfile = true
    encrypt      = true

    assume_role = {
      role_arn     = "arn:aws:iam::486949319589:role/tt-terraform-deployer"
      session_name = "terraform-local-dev"
    }
  }
}

provider "aws" {
  region = "us-east-1"

  assume_role {
    role_arn     = "arn:aws:iam::486949319589:role/tt-terraform-deployer"
    session_name = "terraform-local"
  }

  default_tags {
    tags = {
      ManagedBy = "terraform"
    }
  }
}
