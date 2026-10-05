output "id" {
  description = "The ID of the Storage Account"
  value       = azurerm_storage_account.this.id
}

output "name" {
  description = "The name of the Storage Account"
  value       = azurerm_storage_account.this.name
}

output "primary_blob_endpoint" {
  description = "The endpoint URL for blob storage"
  value       = azurerm_storage_account.this.primary_blob_endpoint
}

output "primary_access_key" {
  description = "The primary access key for the storage account"
  value       = azurerm_storage_account.this.primary_access_key
  sensitive   = true
}

output "identity_principal_id" {
  description = "The Principal ID for the Managed Identity of this Storage Account"
  value       = try(azurerm_storage_account.this.identity[0].principal_id, null)
}

output "identity_tenant_id" {
  description = "The Tenant ID for the Managed Identity of this Storage Account"
  value       = try(azurerm_storage_account.this.identity[0].tenant_id, null)
}
