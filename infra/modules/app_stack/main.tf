# Default tags for all resources in this module
locals {
  name = "tt-${var.env_name}"

  tags = merge(var.tags, {
    Project     = "task-tracker"
    Environment = var.env_name
    ManagedBy   = "terraform"
  })

  # AMIs pinned (not floating SSM "latest") so instances aren't replaced on every new AL2023 —
  ami_al2023_arm    = "ami-02e447f4c654c7179" # AL2023 arm64  (NAT)
  ami_al2023_x86_64 = "ami-0fd6240f599091088" # AL2023 x86_64 (app)

  subnets = {
    public_1a  = { az = "us-east-1a", netnum = 1, tier = "public" }
    public_1b  = { az = "us-east-1b", netnum = 2, tier = "public" }
    private_1a = { az = "us-east-1a", netnum = 3, tier = "private" }
    private_1b = { az = "us-east-1b", netnum = 4, tier = "private" }
  }
}

resource "aws_route53_record" "app" {
  zone_id = data.aws_route53_zone.main.zone_id
  name    = var.app_domain_name
  type    = "A"

  alias {
    name                   = aws_lb.app.dns_name
    zone_id                = aws_lb.app.zone_id
    evaluate_target_health = true
  }
}

data "aws_acm_certificate" "alb_cert" {
  domain      = var.app_domain_name
  statuses    = ["ISSUED"]
  most_recent = true
}

data "aws_route53_zone" "main" {
  name         = var.main_domain_name
  private_zone = false
}
