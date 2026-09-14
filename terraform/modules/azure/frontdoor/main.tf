# Azure Front Door Premium Profile with Managed WAF
resource "azurerm_cdn_frontdoor_profile" "this" {
  name                = "${var.name}-${var.environment}-afd"
  resource_group_name = var.resource_group_name
  sku_name            = "Premium_AzureFrontDoor"
  tags                = var.tags
}

# Azure WAF Policy at the Global Edge
resource "azurerm_cdn_frontdoor_firewall_policy" "waf" {
  name                = replace("${var.name}${var.environment}waf", "-", "")
  resource_group_name = var.resource_group_name
  sku_name            = azurerm_cdn_frontdoor_profile.this.sku_name
  enabled             = true
  mode                = "Prevention"

  managed_rule {
    type    = "Microsoft_DefaultRuleSet"
    version = "2.1"
    action  = "Block"
  }

  managed_rule {
    type    = "Microsoft_BotManagerRuleSet"
    version = "1.0"
    action  = "Block"
  }

  tags = var.tags
}

resource "azurerm_cdn_frontdoor_security_policy" "waf_link" {
  name                     = "${var.name}-${var.environment}-sec-policy"
  cdn_frontdoor_profile_id = azurerm_cdn_frontdoor_profile.this.id

  security_policies {
    firewall {
      cdn_frontdoor_firewall_policy_id = azurerm_cdn_frontdoor_firewall_policy.waf.id

      association {
        domain {
          cdn_frontdoor_domain_id = azurerm_cdn_frontdoor_endpoint.this.id
        }
        patterns_to_match = ["/*"]
      }
    }
  }
}

resource "azurerm_cdn_frontdoor_endpoint" "this" {
  name                     = "${var.name}-${var.environment}-ep"
  cdn_frontdoor_profile_id = azurerm_cdn_frontdoor_profile.this.id
  tags                     = var.tags
}

locals {
  clean_storage_host = replace(replace(var.storage_blob_endpoint, "https://", ""), "/", "")
}

# ==============================================================================
# ORIGIN GROUP 1: Static Storage Account (Angular 21 SPA assets)
# ==============================================================================
resource "azurerm_cdn_frontdoor_origin_group" "static_group" {
  name                     = "static-frontend-group"
  cdn_frontdoor_profile_id = azurerm_cdn_frontdoor_profile.this.id

  load_balancing {
    additional_latency_in_milliseconds = 50
    sample_size                        = 4
    successful_samples_required        = 3
  }
}

resource "azurerm_cdn_frontdoor_origin" "static_origin" {
  name                          = "static-storage-origin"
  cdn_frontdoor_origin_group_id = azurerm_cdn_frontdoor_origin_group.static_group.id
  enabled                       = true

  certificate_name_check_enabled = true
  host_name                      = local.clean_storage_host
  http_port                      = 80
  https_port                     = 443
  origin_host_header             = local.clean_storage_host
  priority                       = 1
  weight                         = 1000
}

# Default Route (/*): Serves Angular frontend static assets from Storage Blob
resource "azurerm_cdn_frontdoor_route" "static_route" {
  name                          = "static-frontend-route"
  cdn_frontdoor_endpoint_id     = azurerm_cdn_frontdoor_endpoint.this.id
  cdn_frontdoor_origin_group_id = azurerm_cdn_frontdoor_origin_group.static_group.id
  cdn_frontdoor_origin_ids      = [azurerm_cdn_frontdoor_origin.static_origin.id]

  supported_protocols    = ["Http", "Https"]
  patterns_to_match      = ["/*"]
  forwarding_protocol    = "HttpsOnly"
  link_to_default_domain = true
  https_redirect_enabled = true

  cache {
    query_string_caching_behavior = "IgnoreQueryString"
    compression_enabled           = true
    content_types_to_compress     = ["text/html", "application/javascript", "text/css", "application/json", "image/svg+xml"]
  }
}

# ==============================================================================
# ORIGIN GROUP 2: AKS Standard Load Balancer (Istio ingress gateway dynamic API)
# ==============================================================================
resource "azurerm_cdn_frontdoor_origin_group" "api_group" {
  name                     = "aks-api-group"
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
    interval_in_seconds = 30
  }
}

resource "azurerm_cdn_frontdoor_origin" "api_origin" {
  name                          = "aks-istio-gateway-origin"
  cdn_frontdoor_origin_group_id = azurerm_cdn_frontdoor_origin_group.api_group.id
  enabled                       = true

  certificate_name_check_enabled = var.certificate_name_check_enabled
  host_name                      = var.api_backend_address
  http_port                      = 80
  https_port                     = 443
  origin_host_header             = var.domain_name != "" ? var.domain_name : var.api_backend_address
  priority                       = 1
  weight                         = 1000
}

# API Route (/api/*): Dispatches dynamic API calls to the AKS Istio ingress gateway
resource "azurerm_cdn_frontdoor_route" "api_route" {
  name                          = "api-backend-route"
  cdn_frontdoor_endpoint_id     = azurerm_cdn_frontdoor_endpoint.this.id
  cdn_frontdoor_origin_group_id = azurerm_cdn_frontdoor_origin_group.api_group.id
  cdn_frontdoor_origin_ids      = [azurerm_cdn_frontdoor_origin.api_origin.id]

  supported_protocols    = ["Http", "Https"]
  patterns_to_match      = ["/api/*", "/realms/*"]
  forwarding_protocol    = "MatchRequest"
  link_to_default_domain = true
  https_redirect_enabled = true
}
