# IAM deployment role
data "aws_iam_policy_document" "deployer_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::486949319589:user/Light-admin"]
    }
  }

  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:Light3313@202292607/task-tracker-aws@1301640311:ref:refs/heads/main"]
    }
  }
}

data "aws_iam_policy_document" "deployer_policy" {
  # Service-level scope: every service the stack provisions, listed explicitly.
  # Deliberately broad per service (no permission boundary yet) but never *:*.
  statement {
    sid    = "InfraServices"
    effect = "Allow"
    actions = [
      "ec2:*",                     # VPC, subnets, IGW, route tables, SGs, instances, EIP/NAT, ENIs, flow logs, EBS encryption defaults
      "elasticloadbalancing:*",    # ALB, target group, listener, attachment
      "ecs:*",                     # cluster, task definition, service
      "application-autoscaling:*", # ECS service autoscaling target + policy — its own service, not ecs:
      "rds:*",                     # DB instance + subnet group
      "iam:*",                     # app role/instance-profile/policies (+ this deployer role itself)
      "kms:*",                     # storage encryption keys (RDS/EBS default + customer-managed CMK)
      "logs:*",                    # CloudWatch Logs group for VPC flow logs
      "ssm:*",                     # /task-tracker/* parameters + SSM-managed instances + public AMI params
      "secretsmanager:*",          # RDS master password via managed secret
      "ecr:*",                     # ECR repository for Docker image
      "acm:*",                     # ACM certificate for ALB HTTPS listener
      "route53:*",                 # Route 53 hosted zone
    ]
    resources = ["*"]
  }

  # Remote state backend: scoped to the one state bucket, not all of S3.
  statement {
    sid    = "TerraformStateBackend"
    effect = "Allow"
    actions = [
      "s3:ListBucket",
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
    ]
    resources = [
      "arn:aws:s3:::tt-tfstate-486949319589",
      "arn:aws:s3:::tt-tfstate-486949319589/*",
    ]
  }
}

resource "aws_iam_role" "terraform_deployer" {
  name               = "tt-terraform-deployer"
  assume_role_policy = data.aws_iam_policy_document.deployer_trust.json
}

resource "aws_iam_role_policy" "deployer_policy" {
  name   = "tt-terraform-deployer-policy"
  role   = aws_iam_role.terraform_deployer.id
  policy = data.aws_iam_policy_document.deployer_policy.json
}

# IAM deployment read-only role
data "aws_iam_policy_document" "planner_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:Light3313@202292607/task-tracker-aws@1301640311:pull_request"]
    }
  }
}

data "aws_iam_policy_document" "planner_policy" {
  # Assumed from pull requests, i.e. unreviewed code — read-only, no exceptions.
  statement {
    sid    = "ReadStackResources"
    effect = "Allow"
    actions = [
      "ec2:Describe*",                     # VPC, subnets, IGW, route tables, SGs, ENIs, EIPs, instances, flow logs
      "elasticloadbalancing:Describe*",    # load balancer, target group, listeners, target health
      "ecs:Describe*",                     # cluster, service, task definition
      "ecs:List*",                         # ListTagsForResource — ECS tags are a separate API, like RDS
      "application-autoscaling:Describe*", # scalable target + scaling policy
      "application-autoscaling:List*",     # its tags, likewise separate
      "rds:Describe*",                     # DB instance and subnet group
      "rds:ListTagsForResource",           # RDS tags are served by their own API, not by Describe*
      "iam:Get*",                          # roles, inline policies, instance profile
      "iam:List*",
      "kms:Describe*", # storage encryption key and its alias
      "kms:Get*",
      "kms:List*",
      "logs:Describe*",           # flow-log group
      "logs:ListTagsForResource", # log group tags, likewise a separate API
      "acm:Describe*",            # certificate resolved for the HTTPS listener
      "acm:List*",
      "acm:Get*",     # public cert body; the private key needs acm:ExportCertificate, not granted
      "route53:Get*", # hosted zone and the alias record
      "route53:List*",
    ]
    resources = ["*"] # Describe/List take no resource constraint
  }

  # Read-only: plan runs with -lock=false, so it never writes the state file.
  statement {
    sid    = "TerraformStateBackendRead"
    effect = "Allow"
    actions = [
      "s3:ListBucket",
      "s3:GetObject",
    ]
    resources = [
      "arn:aws:s3:::tt-tfstate-486949319589",
      "arn:aws:s3:::tt-tfstate-486949319589/*",
    ]
  }
}

resource "aws_iam_role" "terraform_planner" {
  name               = "tt-terraform-planner"
  assume_role_policy = data.aws_iam_policy_document.planner_trust.json
}

resource "aws_iam_role_policy" "planner_policy" {
  name   = "tt-terraform-planner-policy"
  role   = aws_iam_role.terraform_planner.id
  policy = data.aws_iam_policy_document.planner_policy.json
}

# Connect github iam openid provider
resource "aws_iam_openid_connect_provider" "github" {
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
}

# Account-wide, region-level default: new EBS volumes are encrypted unless a
# resource explicitly opts out. Backstop under the per-volume encrypted = true.
resource "aws_ebs_encryption_by_default" "enabled" {
  enabled = true
}

#trivy:ignore:AVD-AWS-0033 Default encryption is sufficient
resource "aws_ecr_repository" "task_tracker" {
  name                 = "task-tracker"
  image_tag_mutability = "IMMUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }
}

resource "aws_ecr_lifecycle_policy" "task_tracker" {
  repository = aws_ecr_repository.task_tracker.name

  # Keep last 10 images
  policy = <<POLICY
  {
    "rules": [
      {
        "rulePriority": 1,
        "description": "Keep last 10 images",
        "selection": {
          "tagStatus": "any",
          "countType": "imageCountMoreThan",
          "countNumber": 10
        },
        "action": {
          "type": "expire"
        }
      }
    ]
  }
POLICY
}

resource "aws_route53_zone" "main" {
  name = "kukharets.dev"
}

resource "aws_acm_certificate" "main" {
  domain_name               = "kukharets.dev"
  subject_alternative_names = ["www.kukharets.dev"]
  validation_method         = "DNS"

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_acm_certificate" "app" {
  domain_name       = "app.kukharets.dev"
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_route53_record" "main_cert_validation" {
  for_each = {
    for dvo in aws_acm_certificate.main.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }

  allow_overwrite = true
  name            = each.value.name
  records         = [each.value.record]
  ttl             = 60
  type            = each.value.type
  zone_id         = aws_route53_zone.main.zone_id
}

resource "aws_route53_record" "app_cert_validation" {
  for_each = {
    for dvo in aws_acm_certificate.app.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }

  allow_overwrite = true
  name            = each.value.name
  records         = [each.value.record]
  ttl             = 60
  type            = each.value.type
  zone_id         = aws_route53_zone.main.zone_id
}

resource "aws_acm_certificate_validation" "main" {
  certificate_arn         = aws_acm_certificate.main.arn
  validation_record_fqdns = [for record in aws_route53_record.main_cert_validation : record.fqdn]
}

resource "aws_acm_certificate_validation" "app" {
  certificate_arn         = aws_acm_certificate.app.arn
  validation_record_fqdns = [for record in aws_route53_record.app_cert_validation : record.fqdn]
}

# Kept out of the env stack — a key destroyed with it strands its snapshots.
data "aws_iam_policy_document" "rds_kms" {
  statement {
    sid       = "EnableRootAccountAdmin"
    effect    = "Allow"
    actions   = ["kms:*"]
    resources = ["*"]
    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::486949319589:root"]
    }
  }
}

resource "aws_kms_key" "rds_dev" {
  description             = "CMK for tt-dev RDS storage encryption"
  enable_key_rotation     = true
  deletion_window_in_days = 7
  policy                  = data.aws_iam_policy_document.rds_kms.json

  tags = {
    Name        = "tt-dev-rds-kms"
    Project     = "task-tracker"
    Environment = "dev"
  }
}

resource "aws_kms_alias" "rds_dev" {
  name          = "alias/tt-dev-rds"
  target_key_id = aws_kms_key.rds_dev.key_id
}

resource "aws_kms_key" "rds_prod" {
  description             = "CMK for tt-prod RDS storage encryption"
  enable_key_rotation     = true
  deletion_window_in_days = 7
  policy                  = data.aws_iam_policy_document.rds_kms.json

  tags = {
    Name        = "tt-prod-rds-kms"
    Project     = "task-tracker"
    Environment = "prod"
  }
}

resource "aws_kms_alias" "rds_prod" {
  name          = "alias/tt-prod-rds"
  target_key_id = aws_kms_key.rds_prod.key_id
}

# prod keeps its own hostname — dev holds app.kukharets.dev and stays live
resource "aws_acm_certificate" "app_prod" {
  domain_name       = "app-prod.kukharets.dev"
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_route53_record" "app_prod_cert_validation" {
  for_each = {
    for dvo in aws_acm_certificate.app_prod.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }

  allow_overwrite = true
  name            = each.value.name
  records         = [each.value.record]
  ttl             = 60
  type            = each.value.type
  zone_id         = aws_route53_zone.main.zone_id
}

resource "aws_acm_certificate_validation" "app_prod" {
  certificate_arn         = aws_acm_certificate.app_prod.arn
  validation_record_fqdns = [for record in aws_route53_record.app_prod_cert_validation : record.fqdn]
}

# IAM prod deployment role — separate from the dev deployer: prod rights != dev rights
data "aws_iam_policy_document" "deployer_prod_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::486949319589:user/Light-admin"]
    }
  }

  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    # environment:prod — minted only for a job that declared the gated environment,
    # so the approval is what stands between a push and these credentials.
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:Light3313@202292607/task-tracker-aws@1301640311:environment:prod"]
    }
  }
}

data "aws_iam_policy_document" "deployer_prod_policy" {
  statement {
    sid    = "InfraServices"
    effect = "Allow"
    actions = [
      "ec2:*",                     # VPC, subnets, IGW, route tables, SGs, NAT instance, EIP, ENIs, flow logs
      "elasticloadbalancing:*",    # ALB, target group, listeners
      "ecs:*",                     # cluster, task definition, service
      "application-autoscaling:*", # scalable target + policy
      "rds:*",                     # DB instance + subnet group
      "iam:*",                     # task/execution/flow-log roles and their inline policies
      "kms:*",                     # CMK lookup + the grant RDS takes on it
      "logs:*",                    # flow-log and ECS log groups
      "secretsmanager:*",          # manage_master_user_password -> RDS creates the secret
      "route53:*",                 # the alias record for the prod hostname
    ]
    resources = ["*"]
  }

  # Certificate lives in this stack — prod reads it, never issues one.
  # No ecr: at all — the pull is the execution role's job at runtime, not Terraform's.
  statement {
    sid    = "ReadGlobalCertificate"
    effect = "Allow"
    actions = [
      "acm:Describe*",
      "acm:List*",
      "acm:Get*",
    ]
    resources = ["*"]
  }

  # Prod state only — an approved prod apply must not be able to write dev's state.
  statement {
    sid    = "TerraformStateBackend"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
    ]
    resources = ["arn:aws:s3:::tt-tfstate-486949319589/task-tracker/prod/*"]
  }

  # Bucket-level, unscoped — the backend lists on init; the objects are what matter.
  statement {
    sid       = "TerraformStateBucketList"
    effect    = "Allow"
    actions   = ["s3:ListBucket"]
    resources = ["arn:aws:s3:::tt-tfstate-486949319589"]
  }
}

resource "aws_iam_role" "terraform_deployer_prod" {
  name               = "tt-terraform-deployer-prod"
  assume_role_policy = data.aws_iam_policy_document.deployer_prod_trust.json
}

resource "aws_iam_role_policy" "deployer_prod_policy" {
  name   = "tt-terraform-deployer-prod-policy"
  role   = aws_iam_role.terraform_deployer_prod.id
  policy = data.aws_iam_policy_document.deployer_prod_policy.json
}
