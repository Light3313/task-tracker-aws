

resource "aws_iam_account_password_policy" "strict" {
  minimum_password_length        = 14
  require_lowercase_characters   = true
  require_numbers                = true
  require_uppercase_characters   = true
  require_symbols                = true
  allow_users_to_change_password = true
  password_reuse_prevention      = 24
}

resource "aws_accessanalyzer_analyzer" "analyzer" {
  analyzer_name = "account-analyzer-${data.aws_caller_identity.current.account_id}"

  type = "ACCOUNT"
}

# Support role for AWS Support
data "aws_iam_policy_document" "support_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "AWS"
      identifiers = ["arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:root"]
    }
  }
}

resource "aws_iam_role" "aws_support_role" {
  name               = "aws-support-role"
  assume_role_policy = data.aws_iam_policy_document.support_assume_role.json
}

resource "aws_iam_role_policy_attachment" "aws_support_access" {
  role       = aws_iam_role.aws_support_role.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AWSSupportAccess"
}
