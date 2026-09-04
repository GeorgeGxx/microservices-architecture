variable "name" {
  type = string
}

variable "environment" {
  type = string
}

variable "region" {
  type = string
}

variable "project_id" {
  type = string
}

variable "network_name" {
  type = string
}

variable "subnetwork_name" {
  type = string
}

variable "enable_autopilot" {
  type    = bool
  default = true
}

variable "master_cidr" {
  type    = string
  default = "172.16.0.0/28"
}

variable "release_channel" {
  type    = string
  default = "REGULAR"
}
