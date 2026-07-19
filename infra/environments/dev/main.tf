module "app_stack" {
  source = "../../modules/app_stack"

  env_name               = "dev"
  vpc_cidr               = "10.0.0.0/16"
  db_instance_class      = "db.t4g.micro"
  db_multi_az            = false
  db_allocated_storage   = 20
  db_snapshot_identifier = "tt-postgres-preteardown-2026-07-17"
  app_instance_type      = "t3.micro"
  app_image              = "486949319589.dkr.ecr.us-east-1.amazonaws.com/task-tracker:iam-auth"
}
