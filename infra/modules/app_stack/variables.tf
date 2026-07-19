variable "env_name" {
  description = "Environment name (dev/prod) - used in names and tags"
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block for this environment's VPC"
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

variable "app_instance_type" {
  description = "EC2 instance type for the app (example: 't4g.micro')"
  type        = string
}

variable "app_image" {
  description = "ECR image URI for the app container"
  type        = string
}

variable "tags" {
  description = "Extra tags merged into every resource"
  type        = map(string)
  default     = {}
}
