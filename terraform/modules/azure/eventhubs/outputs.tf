output "namespace_id" {
  description = "ID of the EventHub Namespace"
  value       = azurerm_eventhub_namespace.this.id
}

output "kafka_endpoint" {
  description = "The Kafka-compatible endpoint FQDN"
  value       = "${azurerm_eventhub_namespace.this.name}.servicebus.windows.net:9093"
}

output "primary_connection_string" {
  description = "Primary connection string for Kafka SASL authentication"
  value       = azurerm_eventhub_authorization_rule.microservices.primary_connection_string
  sensitive   = true
}

output "orders_topic_name" {
  description = "Event Hub topic name"
  value       = azurerm_eventhub.orders_topic.name
}
