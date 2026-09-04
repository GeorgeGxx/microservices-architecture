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

variable "kubernetes_version" {
  type    = string
  default = "1.30"
}

variable "subnet_id" {
  type = string
}

variable "node_vm_size" {
  type    = string
  default = "Standard_D2s_v5"
}

variable "node_count" {
  type    = number
  default = 2
}

variable "min_count" {
  type    = number
  default = 1
}

variable "max_count" {
  type    = number
  default = 4
}

variable "enable_auto_scaling" {
  type    = bool
  default = true
}

variable "tags" {
  type    = map(string)
  default = {}
}
