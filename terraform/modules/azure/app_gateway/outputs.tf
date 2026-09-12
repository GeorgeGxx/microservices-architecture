output "id" {
  description = "The ID of the Application Gateway"
  value       = azurerm_application_gateway.this.id
}

output "public_ip_address" {
  description = "The Public IP Address of the Application Gateway"
  value       = azurerm_public_ip.this.ip_address
}

output "name" {
  description = "The Name of the Application Gateway"
  value       = azurerm_application_gateway.this.name
}
