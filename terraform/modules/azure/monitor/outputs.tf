output "workspace_id" {
  description = "The ID of the Log Analytics Workspace"
  value       = azurerm_log_analytics_workspace.this.id
}

output "workspace_name" {
  description = "The Name of the Log Analytics Workspace"
  value       = azurerm_log_analytics_workspace.this.name
}

output "instrumentation_key" {
  description = "The Instrumentation Key for Application Insights"
  value       = azurerm_application_insights.this.instrumentation_key
  sensitive   = true
}

output "connection_string" {
  description = "The Connection String for Application Insights"
  value       = azurerm_application_insights.this.connection_string
  sensitive   = true
}
