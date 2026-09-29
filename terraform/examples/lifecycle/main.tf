terraform {
  required_version = ">= 1.8.0"
}

variable "release_revision" {
  description = "Change this value to simulate a rollout trigger. This example creates only terraform_data resources."
  type        = string
  default     = "revision-1"

  validation {
    condition     = length(trimspace(var.release_revision)) > 0
    error_message = "release_revision must not be empty."
  }
}

resource "terraform_data" "release_revision" {
  input = var.release_revision
}

resource "terraform_data" "protected_example" {
  input = "manually-managed-value"

  lifecycle {
    prevent_destroy = true
    ignore_changes  = [input]
  }
}

resource "terraform_data" "workload_example" {
  input = {
    release = terraform_data.release_revision.output
    name    = "sample-workload"
  }

  lifecycle {
    create_before_destroy = true
    replace_triggered_by  = [terraform_data.release_revision]

    precondition {
      condition     = can(regex("^[a-zA-Z0-9][a-zA-Z0-9._-]{0,62}$", var.release_revision))
      error_message = "release_revision must be a short, non-empty revision identifier."
    }

    postcondition {
      condition     = self.output.name == "sample-workload"
      error_message = "The example workload output did not retain its expected name."
    }
  }
}

output "workload_revision" {
  value = terraform_data.workload_example.output.release
}
