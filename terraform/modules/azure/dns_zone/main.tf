resource "azurerm_dns_zone" "this" {
  name                = var.domain_name
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

resource "azurerm_dns_a_record" "apex" {
  count               = var.target_ip != null ? 1 : 0
  name                = "@"
  zone_name           = azurerm_dns_zone.this.name
  resource_group_name = var.resource_group_name
  ttl                 = 300
  records             = [var.target_ip]
  tags                = var.tags
}
