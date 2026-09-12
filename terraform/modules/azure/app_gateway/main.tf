resource "azurerm_public_ip" "this" {
  name                = "${var.name}-${var.environment}-appgw-pip"
  resource_group_name = var.resource_group_name
  location            = var.location
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = var.tags
}

locals {
  gateway_ip_config_name = "appgw-ip-config"
  frontend_port_name     = "appgw-frontend-port"
  frontend_ip_name       = "appgw-frontend-ip"
  backend_pool_name      = "appgw-backend-pool"
  http_setting_name      = "appgw-backend-http-settings"
  listener_name          = "appgw-http-listener"
  routing_rule_name      = "appgw-routing-rule"
  probe_name             = "appgw-health-probe"
}

resource "azurerm_application_gateway" "this" {
  name                = "${var.name}-${var.environment}-appgw"
  resource_group_name = var.resource_group_name
  location            = var.location

  sku {
    name     = "WAF_v2"
    tier     = "WAF_v2"
    capacity = var.sku_capacity
  }

  gateway_ip_configuration {
    name      = local.gateway_ip_config_name
    subnet_id = var.subnet_id
  }

  frontend_port {
    name = local.frontend_port_name
    port = 80
  }

  frontend_ip_configuration {
    name                 = local.frontend_ip_name
    public_ip_address_id = azurerm_public_ip.this.id
  }

  backend_address_pool {
    name         = local.backend_pool_name
    ip_addresses = [var.backend_address]
  }

  backend_http_settings {
    name                  = local.http_setting_name
    cookie_based_affinity = "Disabled"
    port                  = 8080
    protocol              = "Http"
    request_timeout       = 30
    probe_name            = local.probe_name
  }

  probe {
    name                = local.probe_name
    protocol            = "Http"
    path                = "/actuator/health"
    host                = "127.0.0.1"
    interval            = 30
    timeout             = 10
    unhealthy_threshold = 3
  }

  http_listener {
    name                           = local.listener_name
    frontend_ip_configuration_name = local.frontend_ip_name
    frontend_port_name             = local.frontend_port_name
    protocol                       = "Http"
  }

  request_routing_rule {
    name                       = local.routing_rule_name
    rule_type                  = "Basic"
    http_listener_name         = local.listener_name
    backend_address_pool_name  = local.backend_pool_name
    backend_http_settings_name = local.http_setting_name
    priority                   = 100
  }

  waf_configuration {
    enabled          = true
    firewall_mode    = "Prevention"
    rule_set_type    = "OWASP"
    rule_set_version = "3.2"
  }

  tags = var.tags
}
