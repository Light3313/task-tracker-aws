variable "env_name" {
  description = "Environment name (dev/prod) - used in names and tags"
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block for this environment's VPC"
  type        = string
}

variable "app_domain_name" {
  description = "Domain name for the app (example: 'app.example.com')"
  type        = string
}

variable "main_domain_name" {
  description = "Domain name for the Route53 zone (example: 'example.com')"
  type        = string
}

variable "db_instance_class" {
  description = "RDS instance type for the service DB (example: 'db.t4g.micro')"
  type        = string
}

variable "db_multi_az" {
  description = "Whether the RDS instance should be multi-AZ (prod) or single-AZ (dev)"
  type        = bool
}

variable "db_allocated_storage" {
  description = "RDS allocated storage in GB (min 20)"
  type        = number
}

variable "db_snapshot_identifier" {
  description = "Optional snapshot identifier to restore the RDS instance from a snapshot"
  type        = string
}

variable "app_image" {
  description = "ECR image URI for the app container"
  type        = string
}

variable "alert_email" {
  description = "Address subscribed to the alert topic - supplied via TF_VAR_alert_email"
  type        = string

  # An unset GitHub secret arrives as "" -> fail here, not three layers down in the SNS API
  validation {
    condition     = length(trimspace(var.alert_email)) > 0 && strcontains(var.alert_email, "@")
    error_message = "alert_email must be a non-empty address - check the ALERT_EMAIL secret."
  }
}

variable "tags" {
  description = "Extra tags merged into every resource"
  type        = map(string)
  default     = {}
}
