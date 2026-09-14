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

variable "storage_blob_endpoint" {
  description = "Primary blob endpoint hostname of Azure Storage Account serving static frontend"
  type        = string
}

variable "api_backend_address" {
  description = "Public IP or FQDN of the AKS Standard Load Balancer fronting NGINX Ingress"
  type        = string
}

variable "domain_name" {
  description = "Custom domain name (optional)"
  type        = string
  default     = ""
}

variable "certificate_name_check_enabled" {
  description = "Specifies whether certificate name check is enabled"
  type        = bool
  default     = false
}

variable "tags" {
  description = "Resource tags"
  type        = map(string)
  default     = {}
}
