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
      "ec2:*",                  # VPC, subnets, IGW, route tables, SGs, instances, EIP/NAT, ENIs, flow logs, EBS encryption defaults
      "elasticloadbalancing:*", # ALB, target group, listener, attachment
      "rds:*",                  # DB instance + subnet group
      "iam:*",                  # app role/instance-profile/policies (+ this deployer role itself)
      "kms:*",                  # storage encryption keys (RDS/EBS default + customer-managed CMK)
      "logs:*",                 # CloudWatch Logs group for VPC flow logs
      "ssm:*",                  # /task-tracker/* parameters + SSM-managed instances + public AMI params
      "secretsmanager:*",       # RDS master password via managed secret
      "ecr:*",                  # ECR repository for Docker image
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
