# AWS Config for Security Hub controls

locals {
  config_bucket = "config-${data.aws_caller_identity.current.account_id}"

  config_key_prefix = "AWSLogs/${data.aws_caller_identity.current.account_id}/Config/*"
}

resource "aws_iam_service_linked_role" "config" {
  aws_service_name = "config.amazonaws.com"
  description      = "Resource recording for AWS Config"
}

# S3 bucket for configuration history and snapshots
resource "aws_s3_bucket" "config" {
  bucket = local.config_bucket

  tags = { Name = local.config_bucket }
}

resource "aws_s3_bucket_public_access_block" "config" {
  bucket = aws_s3_bucket.config.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "config" {
  bucket = aws_s3_bucket.config.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

#trivy:ignore:AVD-AWS-0132 resource inventory, no secrets
resource "aws_s3_bucket_server_side_encryption_configuration" "config" {
  bucket = aws_s3_bucket.config.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_versioning" "config" {
  bucket = aws_s3_bucket.config.id

  versioning_configuration {
    status = "Enabled"
  }
}

# Target policy has to exist before PutBucketLogging
resource "aws_s3_bucket_logging" "config" {
  depends_on = [aws_s3_bucket_policy.s3_access_logs]

  bucket        = aws_s3_bucket.config.id
  target_bucket = aws_s3_bucket.s3_access_logs.id
  target_prefix = "config-bucket/"
}

resource "aws_s3_bucket_lifecycle_configuration" "config" {
  bucket = aws_s3_bucket.config.id

  depends_on = [aws_s3_bucket_versioning.config]

  rule {
    id     = "expire-config-history"
    status = "Enabled"

    filter {}

    expiration {
      days = 30
    }

    noncurrent_version_expiration {
      noncurrent_days = 7
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

resource "aws_s3_bucket_policy" "config" {
  bucket = aws_s3_bucket.config.id
  policy = data.aws_iam_policy_document.config.json
}

# SLR has no S3 write. Delivery goes through the service principal
data "aws_iam_policy_document" "config" {
  statement {
    sid    = "AWSConfigBucketChecks"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["config.amazonaws.com"]
    }

    actions   = ["s3:GetBucketAcl", "s3:ListBucket"]
    resources = [aws_s3_bucket.config.arn]

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }

  statement {
    sid    = "AWSConfigBucketDelivery"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["config.amazonaws.com"]
    }

    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.config.arn}/${local.config_key_prefix}"]

    condition {
      test     = "StringEquals"
      variable = "s3:x-amz-acl"
      values   = ["bucket-owner-full-control"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }

  statement {
    sid    = "DenyInsecureTransport"
    effect = "Deny"

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    actions   = ["s3:*"]
    resources = [aws_s3_bucket.config.arn, "${aws_s3_bucket.config.arn}/*"]

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_config_configuration_recorder" "this" {
  name     = "account-recorder"
  role_arn = aws_iam_service_linked_role.config.arn

  recording_group {
    all_supported = false

    exclusion_by_resource_types {
      resource_types = ["AWS::Config::ResourceCompliance"]
    }

    recording_strategy {
      use_only = "EXCLUSION_BY_RESOURCE_TYPES"
    }
  }

  recording_mode {
    recording_frequency = "CONTINUOUS"
  }
}

# Snapshots for manual review only — controls run off the change stream
resource "aws_config_delivery_channel" "this" {
  depends_on = [aws_config_configuration_recorder.this, aws_s3_bucket_policy.config]

  name           = "account-channel"
  s3_bucket_name = aws_s3_bucket.config.id

  snapshot_delivery_properties {
    delivery_frequency = "TwentyFour_Hours"
  }
}

resource "aws_config_configuration_recorder_status" "this" {
  depends_on = [aws_config_delivery_channel.this]

  name       = aws_config_configuration_recorder.this.name
  is_enabled = true
}

resource "aws_securityhub_account" "this" {
  enable_default_standards  = false
  control_finding_generator = "SECURITY_CONTROL"
}

resource "aws_securityhub_standards_subscription" "cis" {
  depends_on = [aws_securityhub_account.this, aws_config_configuration_recorder_status.this]

  standards_arn = "arn:${data.aws_partition.current.partition}:securityhub:${data.aws_region.current.region}::standards/cis-aws-foundations-benchmark/v/5.0.0"
}
