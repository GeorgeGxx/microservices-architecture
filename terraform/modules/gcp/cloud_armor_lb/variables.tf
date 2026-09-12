variable "name" {
  type = string
}

variable "environment" {
  type = string
}

variable "domain_name" {
  description = "Domain name for SSL termination (optional)"
  type        = string
  default     = ""
}

variable "rate_limit_count" {
  description = "Maximum requests allowed per client IP per minute before temporary ban"
  type        = number
  default     = 1000
}

variable "labels" {
  type    = map(string)
  default = {}
}
