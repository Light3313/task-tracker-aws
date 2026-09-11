variable "alert_email" {
  description = "Address subscribed to the security alert topic - supplied via TF_VAR_alert_email"
  type        = string

  # An unset variable arrives as "" -> fail here, not three layers down in the SNS API
  validation {
    condition     = length(trimspace(var.alert_email)) > 0 && strcontains(var.alert_email, "@")
    error_message = "alert_email must be a non-empty address - check TF_VAR_alert_email."
  }
}
