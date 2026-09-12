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

variable "domain_name" {
  description = "Custom domain name for Azure DNS Zone (e.g., example.com)"
  type        = string
  default     = ""
}
