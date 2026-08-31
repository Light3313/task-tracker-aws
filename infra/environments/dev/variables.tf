variable "app_image" {
  description = "The image from the ECR repository"
  type        = string
}

variable "alert_email" {
  description = "Address subscribed to the alert topic - supplied via TF_VAR_alert_email"
  type        = string
}
