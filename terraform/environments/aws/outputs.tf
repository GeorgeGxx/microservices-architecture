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

output "alb_dns_name" {
  value = module.alb.dns_name
}
