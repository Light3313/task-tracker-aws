locals {
  tfstate_bucket_arn = "arn:${data.aws_partition.current.partition}:s3:::tt-tfstate-${data.aws_caller_identity.current.account_id}"
}

resource "aws_s3_bucket_policy" "tfstate" {
  bucket = "tt-tfstate-${data.aws_caller_identity.current.account_id}"
  policy = data.aws_iam_policy_document.tfstate.json
}

data "aws_iam_policy_document" "tfstate" {
  statement {
    sid    = "DenyInsecureTransport"
    effect = "Deny"

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    actions   = ["s3:*"]
    resources = [local.tfstate_bucket_arn, "${local.tfstate_bucket_arn}/*"]

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}
