resource "aws_db_subnet_group" "main" {
  name       = "${local.name}-db-subnet-group"
  subnet_ids = [aws_subnet.private_1a.id, aws_subnet.private_1b.id]

  tags = merge(local.tags, { Name = "${local.name}-db-subnet-group" })
}

#trivy:ignore:AVD-AWS-0177 lab is teardown-heavy; deletion protection intentionally off
#trivy:ignore:AVD-AWS-0078 default Performance Insights encryption is sufficient
resource "aws_db_instance" "main" {
  identifier = "${local.name}-postgres"

  allocated_storage                   = var.db_allocated_storage
  snapshot_identifier                 = var.db_snapshot_identifier
  engine                              = "postgres"
  engine_version                      = "18.3"
  instance_class                      = var.db_instance_class
  multi_az                            = var.db_multi_az
  iam_database_authentication_enabled = true
  storage_encrypted                   = true
  publicly_accessible                 = false
  backup_retention_period             = 7
  performance_insights_enabled        = true
  db_subnet_group_name                = aws_db_subnet_group.main.name
  vpc_security_group_ids              = [aws_security_group.sg_rds.id]
  kms_key_id                          = aws_kms_key.rds.arn

  db_name                     = var.db_snapshot_identifier == null ? "tasktracker" : null
  username                    = var.db_snapshot_identifier == null ? "postgres" : null
  manage_master_user_password = true # AWS Secrets Manager for the master password, so let AWS manage it

  # money saver (lab case)
  skip_final_snapshot = true
  deletion_protection = false
}

# CMK 
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

resource "aws_kms_key" "rds" {
  description             = "CMK for ${local.name} RDS storage encryption"
  enable_key_rotation     = true
  deletion_window_in_days = 7
  policy                  = data.aws_iam_policy_document.rds_kms.json

  tags = merge(local.tags, { Name = "${local.name}-rds-kms" })
}

resource "aws_kms_alias" "rds" {
  name          = "alias/${local.name}-rds"
  target_key_id = aws_kms_key.rds.key_id
}
