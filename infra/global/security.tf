data "aws_caller_identity" "current" {}

data "aws_partition" "current" {}

data "aws_region" "current" {}

locals {
  trail_name = "account-trail"

  # String, not aws_cloudtrail.this.arn — that reference closes a cycle (trail depends_on the policy)
  trail_arn = "arn:${data.aws_partition.current.partition}:cloudtrail:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:trail/${local.trail_name}"

  # CloudTrail's own layout — AWSLogs/<account>/CloudTrail/<region>/
  trail_key_prefix = "AWSLogs/${data.aws_caller_identity.current.account_id}/*"
}

# CMK
data "aws_iam_policy_document" "cloudtrail_kms" {
  statement {
    sid    = "EnableIAMUserPermissions"
    effect = "Allow"

    principals {
      type        = "AWS"
      identifiers = ["arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:root"]
    }

    actions   = ["kms:*"]
    resources = ["*"]
  }

  statement {
    sid    = "AllowCloudTrailEncrypt"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }

    actions   = ["kms:GenerateDataKey*", "kms:DescribeKey"]
    resources = ["*"]

    condition {
      test     = "StringLike"
      variable = "kms:EncryptionContext:aws:cloudtrail:arn"
      values   = [local.trail_arn]
    }
  }
}

resource "aws_kms_key" "cloudtrail" {
  description             = "CMK for CloudTrail log encryption"
  enable_key_rotation     = true
  deletion_window_in_days = 7
  policy                  = data.aws_iam_policy_document.cloudtrail_kms.json

  tags = { Name = "cloudtrail-kms" }
}

resource "aws_kms_alias" "cloudtrail" {
  name          = "alias/cloudtrail"
  target_key_id = aws_kms_key.cloudtrail.key_id
}

# IAM role for CloudTrail — CloudWatch Logs delivery only, S3 goes through the bucket policy
data "aws_iam_policy_document" "cloudtrail_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceArn"
      values   = [local.trail_arn]
    }
  }
}

data "aws_iam_policy_document" "cloudtrail_policy" {
  statement {
    effect    = "Allow"
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["${aws_cloudwatch_log_group.cloudtrail_logs.arn}:*"]
  }
}

resource "aws_iam_role" "cloudtrail_to_logs" {
  name               = "cloudtrail-to-logs"
  assume_role_policy = data.aws_iam_policy_document.cloudtrail_assume_role.json
}

resource "aws_iam_role_policy" "cloudtrail_to_logs" {
  name   = "cloudtrail-to-logs-policy"
  role   = aws_iam_role.cloudtrail_to_logs.id
  policy = data.aws_iam_policy_document.cloudtrail_policy.json
}

# S3 bucket for CloudTrail logs
resource "aws_s3_bucket" "cloudtrail_logs" {
  bucket = "cloudtrail-${data.aws_caller_identity.current.account_id}"

  tags = { Name = "cloudtrail-${data.aws_caller_identity.current.account_id}" }
}

resource "aws_s3_bucket_public_access_block" "cloudtrail_logs" {
  bucket = aws_s3_bucket.cloudtrail_logs.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ACLs off -> the bucket policy is the only access path
resource "aws_s3_bucket_ownership_controls" "cloudtrail_logs" {
  bucket = aws_s3_bucket.cloudtrail_logs.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

#trivy:ignore:AVD-AWS-0132 the objects are CMK-encrypted by the trail itself
resource "aws_s3_bucket_server_side_encryption_configuration" "cloudtrail_logs" {
  bucket = aws_s3_bucket.cloudtrail_logs.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Anti-delete
resource "aws_s3_bucket_versioning" "cloudtrail_logs" {
  bucket = aws_s3_bucket.cloudtrail_logs.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_logging" "cloudtrail_logs" {
  bucket        = aws_s3_bucket.cloudtrail_logs.id
  target_bucket = aws_s3_bucket.s3_access_logs.id
  target_prefix = "cloudtrail-bucket/"
}

resource "aws_s3_bucket_policy" "cloudtrail_logs" {
  bucket = aws_s3_bucket.cloudtrail_logs.id
  policy = data.aws_iam_policy_document.cloudtrail_logs.json
}

data "aws_iam_policy_document" "cloudtrail_logs" {
  statement {
    sid    = "AWSCloudTrailAclCheck"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }

    actions   = ["s3:GetBucketAcl"]
    resources = [aws_s3_bucket.cloudtrail_logs.arn]

    condition {
      test     = "StringEquals"
      variable = "aws:SourceArn"
      values   = [local.trail_arn]
    }
  }

  statement {
    sid    = "AWSCloudTrailWrite"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }

    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.cloudtrail_logs.arn}/${local.trail_key_prefix}"]

    condition {
      test     = "StringEquals"
      variable = "s3:x-amz-acl"
      values   = ["bucket-owner-full-control"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceArn"
      values   = [local.trail_arn]
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
    resources = [aws_s3_bucket.cloudtrail_logs.arn, "${aws_s3_bucket.cloudtrail_logs.arn}/*"]

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "cloudtrail_logs" {
  bucket = aws_s3_bucket.cloudtrail_logs.id

  depends_on = [aws_s3_bucket_versioning.cloudtrail_logs]

  rule {
    id     = "expire-trail-logs"
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

# Separate target — a bucket logging into itself loops
resource "aws_s3_bucket" "s3_access_logs" {
  bucket = "s3-access-logs-${data.aws_caller_identity.current.account_id}"

  tags = { Name = "s3-access-logs-${data.aws_caller_identity.current.account_id}" }
}

resource "aws_s3_bucket_public_access_block" "s3_access_logs" {
  bucket = aws_s3_bucket.s3_access_logs.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "s3_access_logs" {
  bucket = aws_s3_bucket.s3_access_logs.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

#trivy:ignore:AVD-AWS-0132 default S3 encryption is sufficient for access logs
resource "aws_s3_bucket_server_side_encryption_configuration" "s3_access_logs" {
  bucket = aws_s3_bucket.s3_access_logs.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_versioning" "s3_access_logs" {
  bucket = aws_s3_bucket.s3_access_logs.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "s3_access_logs" {
  bucket = aws_s3_bucket.s3_access_logs.id

  depends_on = [aws_s3_bucket_versioning.s3_access_logs]

  rule {
    id     = "expire-access-logs"
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

resource "aws_s3_bucket_policy" "s3_access_logs" {
  bucket = aws_s3_bucket.s3_access_logs.id
  policy = data.aws_iam_policy_document.s3_access_logs.json
}

data "aws_iam_policy_document" "s3_access_logs" {
  statement {
    sid    = "S3ServerAccessLogsPolicy"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["logging.s3.amazonaws.com"]
    }

    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.s3_access_logs.arn}/*"]

    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values   = [aws_s3_bucket.cloudtrail_logs.arn, aws_s3_bucket.config.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }

  statement {
    sid    = "ALBAccessLogsPolicy"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["logdelivery.elasticloadbalancing.amazonaws.com"]
    }

    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.s3_access_logs.arn}/alb/AWSLogs/${data.aws_caller_identity.current.account_id}/*"]

    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values   = ["arn:${data.aws_partition.current.partition}:elasticloadbalancing:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:loadbalancer/*"]
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
    resources = [aws_s3_bucket.s3_access_logs.arn, "${aws_s3_bucket.s3_access_logs.arn}/*"]

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

#trivy:ignore:AVD-AWS-0017 default CWL encryption is sufficient
resource "aws_cloudwatch_log_group" "cloudtrail_logs" {
  name = "/aws/cloudtrail/${local.trail_name}"

  retention_in_days = 7
}

resource "aws_cloudtrail" "this" {
  depends_on = [aws_s3_bucket_policy.cloudtrail_logs]

  name                          = local.trail_name
  s3_bucket_name                = aws_s3_bucket.cloudtrail_logs.id
  kms_key_id                    = aws_kms_key.cloudtrail.arn
  cloud_watch_logs_group_arn    = "${aws_cloudwatch_log_group.cloudtrail_logs.arn}:*"
  cloud_watch_logs_role_arn     = aws_iam_role.cloudtrail_to_logs.arn
  enable_log_file_validation    = true
  include_global_service_events = true
  is_multi_region_trail         = true

  event_selector {
    read_write_type           = "All"
    include_management_events = true
  }
}

# Email subscriptions need a manual click
#trivy:ignore:AVD-AWS-0095 payload is a metric name and a state string
resource "aws_sns_topic" "security_alerts" {
  name = "security-alerts"

  tags = { Name = "security-alerts" }
}

resource "aws_sns_topic_subscription" "security_alerts_email" {
  topic_arn = aws_sns_topic.security_alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

# events/cloudwatch have no IAM identity; account roles do and go through IAM
data "aws_iam_policy_document" "security_alerts" {
  statement {
    sid    = "AllowServicePublish"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["events.amazonaws.com", "cloudwatch.amazonaws.com"]
    }

    actions   = ["SNS:Publish"]
    resources = [aws_sns_topic.security_alerts.arn]

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }
}

resource "aws_sns_topic_policy" "security_alerts" {
  arn    = aws_sns_topic.security_alerts.arn
  policy = data.aws_iam_policy_document.security_alerts.json
}

# invokedBy set = AWS calling for the account; AwsServiceEvent = not an API call
resource "aws_cloudwatch_log_metric_filter" "root_account_usage" {
  name           = "root-account-usage"
  log_group_name = aws_cloudwatch_log_group.cloudtrail_logs.name
  pattern        = "{ $.userIdentity.type = \"Root\" && $.userIdentity.invokedBy NOT EXISTS && $.eventType != \"AwsServiceEvent\" }"

  metric_transformation {
    name      = "RootAccountUsage"
    namespace = "Security"
    value     = "1"

    # Without this the metric has no points between hits, so the alarm never leaves INSUFFICIENT_DATA
    default_value = "0"
  }
}

resource "aws_cloudwatch_metric_alarm" "root_account_usage" {
  alarm_name        = "root-account-usage"
  alarm_description = "Root credentials were used"

  namespace   = "Security"
  metric_name = "RootAccountUsage"
  statistic   = "Sum"
  period      = 120

  comparison_operator = "GreaterThanThreshold"
  threshold           = 0
  evaluation_periods  = 1
  datapoints_to_alarm = 1
  treat_missing_data  = "notBreaching"

  alarm_actions = [aws_sns_topic.security_alerts.arn]
  ok_actions    = [aws_sns_topic.security_alerts.arn]

  tags = { Name = "root-account-usage" }
}

# Regional — us-east-1 only, other regions are trail-only
resource "aws_guardduty_detector" "this" {
  enable = true

  finding_publishing_frequency = "FIFTEEN_MINUTES"

  tags = { Name = "account-detector" }
}

resource "aws_guardduty_detector_feature" "this" {
  for_each = {
    S3_DATA_EVENTS         = "ENABLED"  # buckets including the CloudTrail one
    RDS_LOGIN_EVENTS       = "ENABLED"  # tt-dev-postgres
    EKS_AUDIT_LOGS         = "DISABLED" # no EKS
    EKS_RUNTIME_MONITORING = "DISABLED" # no EKS
    LAMBDA_NETWORK_LOGS    = "DISABLED" # no Lambda
    EBS_MALWARE_PROTECTION = "DISABLED" # priced per GB scanned
    RUNTIME_MONITORING     = "DISABLED" # needs a sidecar agent in every Fargate task
  }

  detector_id = aws_guardduty_detector.this.id
  name        = each.key
  status      = each.value

  dynamic "additional_configuration" {
    for_each = try(local.guardduty_agents[each.key], {})

    content {
      name   = additional_configuration.key
      status = additional_configuration.value
    }
  }
}

# Attached by AWS itself — undeclared = drift on every plan
locals {
  guardduty_agents = {
    EKS_RUNTIME_MONITORING = {
      EKS_ADDON_MANAGEMENT = "DISABLED"
    }

    RUNTIME_MONITORING = {
      EC2_AGENT_MANAGEMENT         = "DISABLED"
      ECS_FARGATE_AGENT_MANAGEMENT = "DISABLED" # agent into every Fargate task
      EKS_ADDON_MANAGEMENT         = "DISABLED"
    }
  }
}

resource "aws_cloudwatch_event_rule" "guardduty_findings" {
  name        = "guardduty-findings"
  description = "GuardDuty findings of severity Medium and above"

  event_pattern = jsonencode({
    source        = ["aws.guardduty"]
    "detail-type" = ["GuardDuty Finding"]
    detail = {
      severity = [{ numeric = [">=", 4] }]
    }
  })
}

# Simple message instead of raw JSON
resource "aws_cloudwatch_event_target" "guardduty_to_sns" {
  rule      = aws_cloudwatch_event_rule.guardduty_findings.name
  target_id = "security-alerts"
  arn       = aws_sns_topic.security_alerts.arn

  input_transformer {
    input_paths = {
      severity = "$.detail.severity"
      type     = "$.detail.type"
      region   = "$.detail.region"
      desc     = "$.detail.description"
    }

    input_template = "\"GuardDuty severity <severity> in <region>: <type>. <desc>\""
  }
}
