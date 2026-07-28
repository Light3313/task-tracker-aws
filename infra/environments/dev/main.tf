module "app_stack" {
  source = "../../modules/app_stack"

  env_name               = "dev"
  vpc_cidr               = "10.0.0.0/16"
  app_domain_name        = "app.kukharets.dev"
  main_domain_name       = "kukharets.dev"
  db_instance_class      = "db.t4g.micro"
  db_multi_az            = false
  db_allocated_storage   = 20
  db_snapshot_identifier = "tt-postgres-cmk-2026-07-28"
  app_instance_type      = "t3.micro"
  app_image              = var.app_image
}
