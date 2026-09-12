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

variable "aks_oidc_issuer_url" {
  description = "The OIDC Issuer URL from the AKS cluster"
  type        = string
}

variable "service_account_namespace" {
  description = "Kubernetes namespace for the service account"
  type        = string
  default     = "default"
}

variable "service_account_name" {
  description = "Kubernetes Service Account name"
  type        = string
  default     = "msa-workload-sa"
}

variable "tags" {
  description = "Resource tags"
  type        = map(string)
  default     = {}
}
