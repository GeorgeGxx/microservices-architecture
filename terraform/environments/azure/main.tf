resource "azurerm_resource_group" "this" {
  name     = "${local.name}-${local.env}-rg"
  location = var.location
  tags     = local.tags
}

module "vnet" {
  source = "../../modules/azure/vnet"

  name                = local.name
  environment         = local.env
  location            = var.location
  resource_group_name = azurerm_resource_group.this.name
  vnet_cidr           = local.cfg.vnet_cidr
  aks_subnet_cidr     = local.cfg.aks_subnet_cidr
  db_subnet_cidr      = local.cfg.db_subnet_cidr
  tags                = local.tags
}

module "aks" {
  source = "../../modules/azure/aks"

  name                = local.name
  environment         = local.env
  location            = var.location
  resource_group_name = azurerm_resource_group.this.name
  subnet_id           = module.vnet.aks_subnet_id
  node_vm_size        = local.cfg.node_vm_size
  node_count          = local.cfg.node_count
  min_count           = local.cfg.min_count
  max_count           = local.cfg.max_count
  enable_auto_scaling = true
  tags                = local.tags
}

module "acr" {
  source = "../../modules/azure/acr"

  name                = local.name
  environment         = local.env
  location            = var.location
  resource_group_name = azurerm_resource_group.this.name
  sku                 = local.env == "prod" ? "Premium" : "Standard"
  tags                = local.tags
}

# Attach ACR Pull role to AKS Kubelet identity
resource "azurerm_role_assignment" "aks_acr" {
  scope                = module.acr.acr_id
  role_definition_name = "AcrPull"
  principal_id         = module.aks.kubelet_identity_object_id
}

# Private DNS Zone for PostgreSQL Flexible Server
resource "azurerm_private_dns_zone" "postgres" {
  count               = local.cfg.enable_managed_db ? 1 : 0
  name                = "${local.name}-${local.env}.postgres.database.azure.com"
  resource_group_name = azurerm_resource_group.this.name
  tags                = local.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "postgres" {
  count                 = local.cfg.enable_managed_db ? 1 : 0
  name                  = "${local.name}-${local.env}-psql-link"
  private_dns_zone_name = azurerm_private_dns_zone.postgres[0].name
  virtual_network_id    = module.vnet.vnet_id
  resource_group_name   = azurerm_resource_group.this.name
}

module "postgresql" {
  count  = local.cfg.enable_managed_db ? 1 : 0
  source = "../../modules/azure/postgresql"

  name                   = local.name
  environment            = local.env
  location               = var.location
  resource_group_name    = azurerm_resource_group.this.name
  subnet_id              = module.vnet.db_subnet_id
  private_dns_zone_id    = azurerm_private_dns_zone.postgres[0].id
  sku_name               = local.cfg.db_sku_name
  storage_mb             = local.cfg.db_storage_mb
  postgres_version       = "16"
  administrator_login    = "psqladmin"
  administrator_password = var.administrator_password
  high_availability      = local.cfg.db_ha
  database_names         = local.database_names
  tags                   = local.tags

  depends_on = [azurerm_private_dns_zone_virtual_network_link.postgres]
}

data "azurerm_client_config" "current" {}

module "keyvault" {
  source = "../../modules/azure/keyvault"

  name                           = local.name
  environment                    = local.env
  location                       = var.location
  resource_group_name            = azurerm_resource_group.this.name
  tenant_id                      = data.azurerm_client_config.current.tenant_id
  aks_kubelet_identity_object_id = module.aks.kubelet_identity_object_id
  tags                           = local.tags
}
