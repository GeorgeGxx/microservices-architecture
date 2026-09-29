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

variable "subnet_id" {
  type = string
}

variable "private_dns_zone_id" {
  type = string
}

variable "sku_name" {
  type    = string
  default = "B_Standard_B1ms"
}

variable "storage_mb" {
  type    = number
  default = 32768
}

variable "postgres_version" {
  type    = string
  default = "18"
}

variable "administrator_login" {
  type    = string
  default = "psqladmin"
}

variable "administrator_password" {
  type      = string
  sensitive = true
}

variable "high_availability" {
  type    = bool
  default = false
}

variable "backup_retention_days" {
  description = "Automated backup retention in days (Azure supports 7-35 days)."
  type        = number
  default     = 7

  validation {
    condition     = var.backup_retention_days >= 7 && var.backup_retention_days <= 35
    error_message = "Azure PostgreSQL backup retention must be between 7 and 35 days."
  }
}

variable "database_names" {
  type = list(string)
  default = [
    "ms_products",
    "ms_inventory",
    "ms_orders",
    "keycloak_db"
  ]
}

variable "tags" {
  type    = map(string)
  default = {}
}
