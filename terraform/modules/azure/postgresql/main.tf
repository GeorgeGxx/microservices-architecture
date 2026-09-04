resource "azurerm_postgresql_flexible_server" "this" {
  name                = "${var.name}-${var.environment}-psql"
  location            = var.location
  resource_group_name = var.resource_group_name

  delegated_subnet_id = var.subnet_id
  private_dns_zone_id = var.private_dns_zone_id

  sku_name   = var.sku_name
  storage_mb = var.storage_mb
  version    = var.postgres_version

  administrator_login    = var.administrator_login
  administrator_password = var.administrator_password

  dynamic "high_availability" {
    for_each = var.high_availability ? [1] : []
    content {
      mode = "ZoneRedundant"
    }
  }

  tags = var.tags
}

resource "azurerm_postgresql_flexible_server_database" "this" {
  for_each  = toset(var.database_names)
  name      = each.value
  server_id = azurerm_postgresql_flexible_server.this.id
  collation = "en_US.utf8"
  charset   = "utf8"
}
