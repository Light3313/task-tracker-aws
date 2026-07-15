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
    key          = "task-tracker/terraform.tfstate"
    region       = "us-east-1"
    use_lockfile = true
    encrypt      = true
  }
}


