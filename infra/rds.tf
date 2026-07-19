resource "aws_db_subnet_group" "main" {
  name       = "tt-db-subnet-group"
  subnet_ids = [aws_subnet.private_1a.id, aws_subnet.private_1b.id]

  tags = {
    Name = "tt-db-subnet-group"
  }
}

#trivy:ignore:AVD-AWS-0177 lab is teardown-heavy; deletion protection intentionally off
#trivy:ignore:AVD-AWS-0078 default Performance Insights encryption is sufficient
resource "aws_db_instance" "main" {
  identifier = "tt-postgres"

  allocated_storage                   = 20
  engine                              = "postgres"
  engine_version                      = "18.3"
  instance_class                      = "db.t4g.micro"
  multi_az                            = false
  iam_database_authentication_enabled = true
  storage_encrypted                   = true
  publicly_accessible                 = false
  backup_retention_period             = 7
  performance_insights_enabled        = true
  db_subnet_group_name                = aws_db_subnet_group.main.name
  vpc_security_group_ids              = [aws_security_group.sg_rds.id]

  db_name                     = "tasktracker"
  username                    = "postgres"
  manage_master_user_password = true # AWS Secrets Manager for the master password, so let AWS manage it

  # money saver (lab case)
  skip_final_snapshot = true
  deletion_protection = false
}
