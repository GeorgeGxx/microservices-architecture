variable "name" {
  type = string
}

variable "environment" {
  type = string
}

variable "location" {
  type    = string
  default = "eastus"
}

variable "resource_group_name" {
  type = string
}

variable "tenant_id" {
  type = string
}

variable "aks_kubelet_identity_object_id" {
  description = "Grants AKS pods (via Workload Identity) permission to read secrets"
  type        = string
}

variable "tags" {
  type    = map(string)
  default = {}
}
