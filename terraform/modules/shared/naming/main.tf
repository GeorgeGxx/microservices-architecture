# Pure-logic module: centralizes naming conventions so AWS and Azure
# environments produce consistent, predictable resource names.
locals {
  prefix = "${var.project}-${var.cloud}-${var.environment}"
}

output "prefix" {
  value = local.prefix
}

output "tags" {
  value = {
    Project     = var.project
    Environment = var.environment
    Cloud       = var.cloud
    ManagedBy   = "terraform"
  }
}
