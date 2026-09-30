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

variable "enable_monthly_cost_budget" {
  description = "Create an Azure subscription monthly consumption budget. This sends alerts only; it does not stop or scale resources."
  type        = bool
  default     = false
}

variable "monthly_cost_budget_usd" {
  description = "Optional monthly USD budget limit by Terraform workspace (dev/staging/prod). Required when enable_monthly_cost_budget is true."
  type        = map(number)
  default     = {}
}

variable "finops_alert_emails" {
  description = "Email recipients for Azure actual and forecast budget alerts."
  type        = list(string)
  default     = []
}
