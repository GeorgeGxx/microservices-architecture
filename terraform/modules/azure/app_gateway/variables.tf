variable "name" {
  description = "Base resource name prefix"
  type        = string
}

variable "environment" {
  description = "Target environment (dev, staging, prod)"
  type        = string
}

variable "location" {
  description = "Azure region location"
  type        = string
}

variable "resource_group_name" {
  description = "Name of the resource group"
  type        = string
}

variable "subnet_id" {
  description = "Subnet ID dedicated to Application Gateway"
  type        = string
}

variable "sku_capacity" {
  description = "Capacity instance count (e.g. 1 for dev, 2 for staging/prod)"
  type        = number
  default     = 2
}

variable "backend_address" {
  description = "Backend address / FQDN (e.g. internal ingress IP or private DNS name of AKS ingress)"
  type        = string
  default     = "10.50.0.100"
}

variable "tags" {
  description = "Resource tags"
  type        = map(string)
  default     = {}
}
