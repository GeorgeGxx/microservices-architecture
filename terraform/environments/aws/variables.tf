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

# terraform.workspace ("dev" | "prod") drives sizing decisions in locals.tf
