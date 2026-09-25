variable "name" {
  type = string
}

variable "environment" {
  type = string
}

variable "engine_version" {
  type    = string
  default = "18.0"
}

variable "instance_class" {
  type    = string
  default = "db.t3.micro"
}

variable "allocated_storage" {
  type    = number
  default = 20
}

variable "db_name" {
  type = string
}

variable "master_username" {
  type    = string
  default = "postgres"
}

variable "master_password" {
  description = "Pass via TF_VAR_master_password or a secrets backend, never commit in plain text"
  type        = string
  sensitive   = true
}

variable "vpc_id" {
  type = string
}

variable "private_subnet_ids" {
  type = list(string)
}

variable "allowed_security_group_ids" {
  description = "SGs (e.g. EKS node SG) allowed to reach the DB on 5432"
  type        = list(string)
  default     = []
}

variable "multi_az" {
  type    = bool
  default = false
}

variable "deletion_protection" {
  type    = bool
  default = false
}

variable "backup_retention_days" {
  type    = number
  default = 7
}

variable "tags" {
  type    = map(string)
  default = {}
}
