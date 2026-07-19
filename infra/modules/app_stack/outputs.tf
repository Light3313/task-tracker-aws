output "app_url" {
  value       = aws_lb.app.dns_name
  description = "The URL of the task tracker app"
}
