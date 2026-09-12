output "dns_name" {
  value = aws_lb.this.dns_name
}

output "zone_id" {
  description = "Route53 hosted zone ID of the ALB, used for alias records"
  value       = aws_lb.this.zone_id
}

output "target_group_arn" {
  value = aws_lb_target_group.gateway.arn
}
