variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Project name"
  type        = string
  default     = "microservices"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "compact-prod"
}

variable "instance_type" {
  description = "EC2 instance type (t3.xlarge: 4 vCPU, 16 GB RAM is recommended for complete container stack)"
  type        = string
  default     = "t3.xlarge"
}

variable "key_pair_name" {
  description = "AWS EC2 Key Pair name for SSH"
  type        = string
  default     = "microservices-deploy-key"
}

variable "root_volume_size" {
  description = "Root GP3 EBS volume size in GiB"
  type        = number
  default     = 60
}

variable "ssh_private_key_path" {
  description = "Local filesystem path to private SSH key for Ansible"
  type        = string
  default     = "~/.ssh/id_rsa"
}

variable "admin_cidr" {
  description = "CIDR block permitted for SSH management"
  type        = string

  validation {
    condition     = can(cidrhost(var.admin_cidr, 0)) && var.admin_cidr != "0.0.0.0/0"
    error_message = "admin_cidr must be a valid, restricted CIDR and must not allow all IPv4 sources."
  }
}
