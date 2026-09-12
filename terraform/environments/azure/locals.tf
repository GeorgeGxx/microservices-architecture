locals {
  name = "msa-azure"
  env  = contains(["dev", "staging", "prod"], terraform.workspace) ? terraform.workspace : "dev"

  tags = {
    Project            = "microservices-architecture"
    Environment        = local.env
    ManagedBy          = "terraform"
    Cloud              = "azure"
    Owner              = "devops-team"
    CostCenter         = "engineering-${local.env}"
    SecurityCompliance = "standard"
  }

  database_names = [
    "ms_products",
    "ms_inventory",
    "ms_orders",
    "keycloak_db"
  ]

  env_config = {
    dev = {
      vnet_cidr           = "10.50.0.0/16"
      aks_subnet_cidr     = "10.50.0.0/20"
      db_subnet_cidr      = "10.50.16.0/24"
      appgw_subnet_cidr   = "10.50.32.0/24"
      node_vm_size        = "Standard_D2s_v5"
      node_count          = 2
      min_count           = 1
      max_count           = 3
      enable_managed_db   = false
      db_sku_name         = "B_Standard_B1ms"
      db_storage_mb       = 32768
      db_ha               = false
      enable_app_gateway  = false
      enable_frontdoor    = false
      enable_redis        = false
      redis_sku           = "Basic"
      redis_family        = "C"
      redis_capacity      = 0
      enable_eventhubs    = false
      eventhubs_sku       = "Standard"
      eventhubs_capacity  = 1
      storage_tier        = "Standard"
      storage_replication = "LRS"
      keyvault_sku        = "standard"
    }
    staging = {
      vnet_cidr           = "10.55.0.0/16"
      aks_subnet_cidr     = "10.55.0.0/20"
      db_subnet_cidr      = "10.55.16.0/24"
      appgw_subnet_cidr   = "10.55.32.0/24"
      node_vm_size        = "Standard_D4s_v5"
      node_count          = 2
      min_count           = 2
      max_count           = 4
      enable_managed_db   = true
      db_sku_name         = "GP_Standard_D2s_v3"
      db_storage_mb       = 65536
      db_ha               = false
      enable_app_gateway  = true
      enable_frontdoor    = true
      enable_redis        = true
      redis_sku           = "Standard"
      redis_family        = "C"
      redis_capacity      = 1
      enable_eventhubs    = true
      eventhubs_sku       = "Standard"
      eventhubs_capacity  = 1
      storage_tier        = "Standard"
      storage_replication = "LRS"
      keyvault_sku        = "standard"
    }
    prod = {
      vnet_cidr           = "10.60.0.0/16"
      aks_subnet_cidr     = "10.60.0.0/20"
      db_subnet_cidr      = "10.60.16.0/24"
      appgw_subnet_cidr   = "10.60.32.0/24"
      node_vm_size        = "Standard_D4s_v5"
      node_count          = 3
      min_count           = 3
      max_count           = 6
      enable_managed_db   = true
      db_sku_name         = "GP_Standard_D4s_v3"
      db_storage_mb       = 131072
      db_ha               = true
      enable_app_gateway  = true
      enable_frontdoor    = true
      enable_redis        = true
      redis_sku           = "Premium"
      redis_family        = "P"
      redis_capacity      = 1
      enable_eventhubs    = true
      eventhubs_sku       = "Standard"
      eventhubs_capacity  = 2
      storage_tier        = "Standard"
      storage_replication = "GRS"
      keyvault_sku        = "standard"
    }
  }

  cfg = local.env_config[local.env]
}
