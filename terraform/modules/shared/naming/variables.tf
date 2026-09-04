variable "project" {
  type    = string
  default = "georgegxx-msa"
}

variable "environment" {
  type = string
}

variable "cloud" {
  description = "aws | azure | local"
  type        = string
}
