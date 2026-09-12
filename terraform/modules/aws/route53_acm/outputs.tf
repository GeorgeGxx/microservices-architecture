output "zone_id" {
  description = "Route53 Hosted Zone ID"
  value       = local.zone_id
}

output "certificate_arn" {
  description = "The ARN of the validated ACM certificate"
  value       = aws_acm_certificate_validation.this.certificate_arn
}

output "domain_name" {
  description = "Domain name registered"
  value       = var.domain_name
}
