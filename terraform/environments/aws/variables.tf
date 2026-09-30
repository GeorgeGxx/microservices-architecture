variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "azs" {
  type    = list(string)
  default = ["us-east-1a", "us-east-1b"]
}

variable "db_master_password" {
  type      = string
  sensitive = true
}

variable "enable_monthly_cost_budget" {
  description = "Create an AWS Budgets monthly cost threshold. This sends alerts only; it does not stop or scale resources."
  type        = bool
  default     = false
}

variable "monthly_cost_budget_usd" {
  description = "Optional monthly USD budget limit by Terraform workspace (dev/staging/prod). Required when enable_monthly_cost_budget is true."
  type        = map(number)
  default     = {}
}

variable "finops_alert_emails" {
  description = "Email recipients for AWS actual and forecast budget alerts."
  type        = list(string)
  default     = []
}

# terraform.workspace ("dev" | "prod") drives sizing decisions in locals.tf
