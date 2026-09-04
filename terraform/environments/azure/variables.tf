variable "location" {
  description = "Azure region for resource deployment"
  type        = string
  default     = "eastus"
}

variable "administrator_password" {
  description = "Master password for Azure Database for PostgreSQL Flexible Server"
  type        = string
  sensitive   = true
  default     = ""
}
