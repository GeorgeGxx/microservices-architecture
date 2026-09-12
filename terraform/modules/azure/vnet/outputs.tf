output "vnet_id" {
  value = azurerm_virtual_network.this.id
}

output "aks_subnet_id" {
  value = azurerm_subnet.aks.id
}

output "db_subnet_id" {
  value = azurerm_subnet.db.id
}

output "appgw_subnet_id" {
  value       = try(azurerm_subnet.appgw[0].id, null)
  description = "Application Gateway subnet ID"
}
