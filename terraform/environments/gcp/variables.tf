variable "project_id" {
  description = "GCP Project ID"
  type        = string
  default     = "microservices-architecture-dev"
}

variable "region" {
  description = "GCP Region for resource deployment"
  type        = string
  default     = "us-central1"
}

variable "db_username" {
  description = "Cloud SQL master username"
  type        = string
  default     = "postgres"
}

variable "db_password" {
  description = "Cloud SQL master password"
  type        = string
  sensitive   = true
  default     = "secure_master_password"
}

variable "domain_name" {
  description = "Custom domain name for Cloud DNS and SSL termination (e.g. example.com)"
  type        = string
  default     = ""
}

variable "alert_email" {
  description = "Email address to receive monitoring alerts"
  type        = string
  default     = ""
}
