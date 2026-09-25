output "fqdn" {
  value = azurerm_postgresql_flexible_server.this.fqdn
}

output "server_fqdn" {
  description = "The fully qualified domain name of the PostgreSQL Flexible Server"
  value       = azurerm_postgresql_flexible_server.this.fqdn
}
