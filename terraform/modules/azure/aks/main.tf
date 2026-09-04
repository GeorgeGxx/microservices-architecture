resource "azurerm_kubernetes_cluster" "this" {
  name                = "${var.name}-${var.environment}-aks"
  location            = var.location
  resource_group_name = var.resource_group_name
  dns_prefix          = "${var.name}-${var.environment}"
  kubernetes_version  = var.kubernetes_version

  default_node_pool {
    name                = "system"
    vm_size             = var.node_vm_size
    vnet_subnet_id      = var.subnet_id
    node_count          = var.node_count
    min_count           = var.enable_auto_scaling ? var.min_count : null
    max_count           = var.enable_auto_scaling ? var.max_count : null
    enable_auto_scaling = var.enable_auto_scaling
  }

  identity {
    type = "SystemAssigned"
  }

  network_profile {
    network_plugin = "azure"
    network_policy = "azure"
  }

  # Enables Azure AD Workload Identity - the Azure equivalent of AWS IRSA,
  # used for pod-level access to Key Vault, ACR, or other Azure services
  # without static credentials.
  oidc_issuer_enabled       = true
  workload_identity_enabled = true

  tags = var.tags
}
