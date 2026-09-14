output "cluster_name" {
  value = module.eks.cluster_name
}

output "cluster_endpoint" {
  value = module.eks.cluster_endpoint
}

output "ecr_repository_urls" {
  value = module.ecr.repository_urls
}

output "rds_postgres_endpoint" {
  value     = try(module.rds_postgres[0].endpoint, "in-cluster-dataplane")
  sensitive = true
}

output "nlb_dns_name" {
  value       = module.nlb.dns_name
  description = "AWS Network Load Balancer (NLB) DNS name fronting Traefik"
}

output "kms_key_arn" {
  description = "KMS Key ARN"
  value       = try(module.kms[0].key_arn, null)
}

output "s3_assets_bucket" {
  description = "S3 Assets Bucket Name"
  value       = try(module.s3_assets[0].bucket_id, null)
}

output "elasticache_redis_endpoint" {
  description = "ElastiCache Redis Primary Endpoint"
  value       = try(module.elasticache_redis[0].primary_endpoint_address, "in-cluster-redis")
}

output "msk_bootstrap_brokers_tls" {
  description = "MSK Kafka Bootstrap Brokers TLS"
  value       = try(module.msk_kafka[0].bootstrap_brokers_tls, "in-cluster-kafka")
}

output "cloudfront_domain_name" {
  description = "CloudFront Distribution Domain Name"
  value       = try(module.cloudfront[0].domain_name, null)
}

output "route53_domain_name" {
  description = "Route53 Registered Domain Name"
  value       = try(module.route53_acm[0].domain_name, null)
}

output "cloudwatch_log_group" {
  description = "CloudWatch Microservices Log Group"
  value       = module.cloudwatch.log_group_name
}

