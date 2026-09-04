resource "azurerm_container_registry" "this" {
  name                = replace("${var.name}${var.environment}acr", "-", "")
  location            = var.location
  resource_group_name = var.resource_group_name
  sku                 = var.sku
  admin_enabled       = false # use AKS kubelet managed identity (AcrPull role) instead

  tags = var.tags
}
