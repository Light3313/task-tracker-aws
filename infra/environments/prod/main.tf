module "app_stack" {
  source = "../../modules/app_stack"

  env_name               = "prod"
  vpc_cidr               = "10.1.0.0/16"
  app_domain_name        = "app-prod.kukharets.dev"
  main_domain_name       = "kukharets.dev"
  db_instance_class      = "db.t4g.medium"
  db_multi_az            = true
  db_allocated_storage   = 40
  db_snapshot_identifier = null
  app_image              = var.app_image
  alert_email            = var.alert_email
}
