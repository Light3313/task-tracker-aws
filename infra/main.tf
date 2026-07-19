provider "aws" {
  region = "us-east-1"

  default_tags {
    tags = {
      ManagedBy = "terraform"
    }
  }

  assume_role {
    role_arn     = "arn:aws:iam::486949319589:role/tt-terraform-deployer"
    session_name = "terraform-local"
  }
}
