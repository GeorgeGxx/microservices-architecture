output "id" {
  description = "The ID of the DNS Zone"
  value       = azurerm_dns_zone.this.id
}

output "name_servers" {
  description = "A list of values that make up the NS record for the zone"
  value       = azurerm_dns_zone.this.name_servers
}
