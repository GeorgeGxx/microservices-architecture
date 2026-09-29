output "resource_group_name" {
  value = azurerm_resource_group.this.name
}

output "microservices_chart_repository" {
  description = "Immutable GHCR OCI repository consumed by application deployment pipelines."
  value       = local.microservices_chart_repository
}

output "microservices_chart_version" {
  description = "Pinned umbrella chart version from helm/microservices-umbrella/Chart.yaml."
  value       = local.microservices_chart.version
}

output "microservices_chart_reference" {
  description = "Version-pinned GHCR chart reference; Terraform provisions infrastructure, CI/GitOps deploys this artifact."
  value       = "${local.microservices_chart_repository}:${local.microservices_chart.version}"
}

output "vnet_id" {
  value = module.vnet.vnet_id
}

output "aks_cluster_name" {
  value = module.aks.cluster_name
}

output "production_dataplane_2_aks_cluster_name" {
  description = "Second independent production AKS data-plane cluster; null outside prod."
  value       = try(module.aks_dp2[0].cluster_name, null)
}

output "aks_oidc_issuer_url" {
  value = module.aks.oidc_issuer_url
}

output "acr_login_server" {
  value = module.acr.login_server
}

output "keyvault_uri" {
  value = module.keyvault.vault_uri
}

output "monitor_log_analytics_workspace_id" {
  value = module.monitor.workspace_id
}

output "workload_identity_client_id" {
  value = module.workload_identity.client_id
}

output "storage_account_name" {
  value = module.storage_account.name
}

output "storage_primary_blob_endpoint" {
  value = module.storage_account.primary_blob_endpoint
}

output "postgresql_fqdn" {
  value = try(module.postgresql[0].server_fqdn, null)
}

output "postgresql_admin_password" {
  value       = local.cfg.enable_managed_db ? local.postgres_admin_password : null
  sensitive   = true
  description = "PostgreSQL administrator password (auto-generated or configured)"
}


output "redis_hostname" {
  value = try(module.redis[0].hostname, null)
}

output "redis_ssl_port" {
  value = try(module.redis[0].ssl_port, null)
}

output "eventhubs_kafka_endpoint" {
  value = try(module.eventhubs[0].kafka_endpoint, null)
}

output "istio_ingress_public_ip" {
  value       = azurerm_public_ip.istio_gateway_public_ip.ip_address
  description = "Public IP address for AKS Standard Load Balancer fronting the Istio ingress gateway"
}

output "frontdoor_endpoint" {
  value = try(module.frontdoor[0].endpoint_host_name, null)
}

output "dns_zone_name_servers" {
  value = try(module.dns_zone[0].name_servers, null)
}
