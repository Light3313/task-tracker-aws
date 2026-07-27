output "alb_url" {
  value       = aws_lb.app.dns_name
  description = "The URL of the task tracker ALB"
}

output "app_url" {
  value       = aws_route53_record.app.fqdn
  description = "The URL of the task tracker app"
}
