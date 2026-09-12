resource "azurerm_user_assigned_identity" "this" {
  name                = "${var.name}-${var.environment}-${var.service_account_name}-id"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

resource "azurerm_federated_identity_credential" "this" {
  name                = "${var.name}-${var.environment}-${var.service_account_name}-fic"
  resource_group_name = var.resource_group_name
  audience            = ["api://AzureADTokenExchange"]
  issuer              = var.aks_oidc_issuer_url
  parent_id           = azurerm_user_assigned_identity.this.id
  subject             = "system:serviceaccount:${var.service_account_namespace}:${var.service_account_name}"
}
