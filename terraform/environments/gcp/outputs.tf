output "gke_cluster_name" {
  value = module.gke.cluster_name
}

output "gke_endpoint" {
  value     = module.gke.cluster_endpoint
  sensitive = true
}

output "artifact_registry_id" {
  value = module.gar.repository_id
}

output "vpc_network_name" {
  value = module.vpc.network_name
}
