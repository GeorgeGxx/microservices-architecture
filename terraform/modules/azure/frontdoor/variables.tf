variable "name" {
  description = "Base resource name prefix"
  type        = string
}

variable "environment" {
  description = "Target environment (dev, staging, prod)"
  type        = string
}

variable "resource_group_name" {
  description = "Name of the resource group"
  type        = string
}

variable "origin_host_header" {
  description = "Host header sent to the origin"
  type        = string
  default     = null
}

variable "origin_address" {
  description = "Public IP or FQDN of the backend (e.g. Application Gateway Public IP)"
  type        = string
}

variable "certificate_name_check_enabled" {
  description = "Specifies whether certificate name check is enabled"
  type        = bool
  default     = false
}

variable "sku_name" {
  description = "SKU for Front Door profile (Standard_AzureFrontDoor or Premium_AzureFrontDoor)"
  type        = string
  default     = "Standard_AzureFrontDoor"
}

variable "tags" {
  description = "Resource tags"
  type        = map(string)
  default     = {}
}
