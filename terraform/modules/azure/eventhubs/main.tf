resource "azurerm_eventhub_namespace" "this" {
  name                = "${var.name}-${var.environment}-ehns"
  location            = var.location
  resource_group_name = var.resource_group_name
  sku                 = var.sku
  capacity            = var.capacity
  minimum_tls_version = "1.2"

  tags = var.tags
}

resource "azurerm_eventhub" "orders_topic" {
  name                = "orders-topic"
  namespace_name      = azurerm_eventhub_namespace.this.name
  resource_group_name = var.resource_group_name
  partition_count     = var.partition_count
  message_retention   = var.message_retention
}

resource "azurerm_eventhub_consumer_group" "notifications" {
  name                = "notification-service-group"
  namespace_name      = azurerm_eventhub_namespace.this.name
  eventhub_name       = azurerm_eventhub.orders_topic.name
  resource_group_name = var.resource_group_name
}

resource "azurerm_eventhub_authorization_rule" "microservices" {
  name                = "msa-kafka-auth"
  namespace_name      = azurerm_eventhub_namespace.this.name
  resource_group_name = var.resource_group_name
  listen              = true
  send                = true
  manage              = false
}
