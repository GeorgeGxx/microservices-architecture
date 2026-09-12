resource "azurerm_cdn_frontdoor_profile" "this" {
  name                = "${var.name}-${var.environment}-afd"
  resource_group_name = var.resource_group_name
  sku_name            = var.sku_name
  tags                = var.tags
}

resource "azurerm_cdn_frontdoor_endpoint" "this" {
  name                     = "${var.name}-${var.environment}-ep"
  cdn_frontdoor_profile_id = azurerm_cdn_frontdoor_profile.this.id
  tags                     = var.tags
}

resource "azurerm_cdn_frontdoor_origin_group" "this" {
  name                     = "primary-origin-group"
  cdn_frontdoor_profile_id = azurerm_cdn_frontdoor_profile.this.id

  load_balancing {
    additional_latency_in_milliseconds = 50
    sample_size                        = 4
    successful_samples_required        = 3
  }

  health_probe {
    path                = "/actuator/health"
    request_type        = "HEAD"
    protocol            = "Http"
    interval_in_seconds = 60
  }
}

resource "azurerm_cdn_frontdoor_origin" "this" {
  name                          = "primary-origin"
  cdn_frontdoor_origin_group_id = azurerm_cdn_frontdoor_origin_group.this.id
  enabled                       = true

  certificate_name_check_enabled = var.certificate_name_check_enabled
  host_name                      = var.origin_address
  http_port                      = 80
  https_port                     = 443
  origin_host_header             = coalesce(var.origin_host_header, var.origin_address)
  priority                       = 1
  weight                         = 1000
}

resource "azurerm_cdn_frontdoor_route" "this" {
  name                          = "default-route"
  cdn_frontdoor_endpoint_id     = azurerm_cdn_frontdoor_endpoint.this.id
  cdn_frontdoor_origin_group_id = azurerm_cdn_frontdoor_origin_group.this.id
  cdn_frontdoor_origin_ids      = [azurerm_cdn_frontdoor_origin.this.id]

  supported_protocols    = ["Http", "Https"]
  patterns_to_match      = ["/*"]
  forwarding_protocol    = "MatchRequest"
  link_to_default_domain = true
  https_redirect_enabled = true
}
