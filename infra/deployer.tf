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
      "kms:*",                  # storage encryption keys (RDS/EBS default + CMK in W6)
      "logs:*",                 # CloudWatch Logs group for VPC flow logs
      "ssm:*",                  # /task-tracker/* parameters + SSM-managed instances + public AMI params
      "secretsmanager:*",       # RDS master password via managed secret (W6)
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
