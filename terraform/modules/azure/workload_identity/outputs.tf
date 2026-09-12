output "client_id" {
  description = "The Client ID of the User Assigned Identity"
  value       = azurerm_user_assigned_identity.this.client_id
}

output "principal_id" {
  description = "The Principal ID of the User Assigned Identity"
  value       = azurerm_user_assigned_identity.this.principal_id
}

output "id" {
  description = "The User Assigned Identity ID"
  value       = azurerm_user_assigned_identity.this.id
}
