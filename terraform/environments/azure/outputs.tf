output "resource_group_name" {
  value = azurerm_resource_group.this.name
}

output "vnet_id" {
  value = module.vnet.vnet_id
}

output "aks_cluster_name" {
  value = module.aks.cluster_name
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

output "redis_hostname" {
  value = try(module.redis[0].hostname, null)
}

output "redis_ssl_port" {
  value = try(module.redis[0].ssl_port, null)
}

output "eventhubs_kafka_endpoint" {
  value = try(module.eventhubs[0].kafka_endpoint, null)
}

output "nginx_ingress_public_ip" {
  value       = azurerm_public_ip.aks_nginx_lb.ip_address
  description = "Public IP address for AKS Standard Load Balancer fronting NGINX Ingress"
}

output "frontdoor_endpoint" {
  value = try(module.frontdoor[0].endpoint_host_name, null)
}

output "dns_zone_name_servers" {
  value = try(module.dns_zone[0].name_servers, null)
}
