output "nlb_arn" {
  value       = aws_lb.this.arn
  description = "ARN of the AWS Network Load Balancer"
}

output "dns_name" {
  value       = aws_lb.this.dns_name
  description = "Public DNS name of the AWS Network Load Balancer"
}

output "zone_id" {
  value       = aws_lb.this.zone_id
  description = "Canonical hosted zone ID of the AWS Network Load Balancer"
}

output "security_group_id" {
  value       = aws_security_group.nlb.id
  description = "Security Group ID of the NLB"
}
