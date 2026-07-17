variable "db_master_password" {
  type      = string
  sensitive = true
}

variable "app_image" {
  description = "full ECR image URI for the app container"
  type        = string
}
