output "log_group_name" {
  description = "Name of the CloudWatch log group"
  value       = aws_cloudwatch_log_group.microservices.name
}

output "log_group_arn" {
  description = "ARN of the CloudWatch log group"
  value       = aws_cloudwatch_log_group.microservices.arn
}

output "dashboard_name" {
  description = "Name of the CloudWatch dashboard created"
  value       = aws_cloudwatch_dashboard.this.dashboard_name
}
