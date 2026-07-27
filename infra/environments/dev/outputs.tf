output "alb_url" {
  value       = module.app_stack.alb_url
  description = "The URL of the task tracker ALB"
}

output "app_url" {
  value       = module.app_stack.app_url
  description = "The URL of the task tracker app"
}
