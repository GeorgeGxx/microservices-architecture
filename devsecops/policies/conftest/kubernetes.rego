package main

import rego.v1

# Deny containers running in privileged mode
deny contains msg if {
  input.kind == "Deployment"
  container := input.spec.template.spec.containers[_]
  container.securityContext.privileged == true
  msg := sprintf("Container '%v' in Deployment '%v' is running in privileged mode. Privileged containers are not allowed.", [container.name, input.metadata.name])
}

# Deny containers without memory/cpu limits
deny contains msg if {
  input.kind == "Deployment"
  container := input.spec.template.spec.containers[_]
  not container.resources.limits
  msg := sprintf("Container '%v' in Deployment '%v' must specify resource limits (cpu & memory).", [container.name, input.metadata.name])
}

# Deny containers using 'latest' tag in image
deny contains msg if {
  input.kind == "Deployment"
  container := input.spec.template.spec.containers[_]
  endswith(container.image, ":latest")
  msg := sprintf("Container '%v' in Deployment '%v' uses the 'latest' image tag. Pin a specific SHA or version tag.", [container.name, input.metadata.name])
}

# Warn if liveness probe is missing on Deployment containers
warn contains msg if {
  input.kind == "Deployment"
  container := input.spec.template.spec.containers[_]
  not container.livenessProbe
  msg := sprintf("Container '%v' in Deployment '%v' does not have a livenessProbe configured.", [container.name, input.metadata.name])
}

# Warn if readiness probe is missing on Deployment containers
warn contains msg if {
  input.kind == "Deployment"
  container := input.spec.template.spec.containers[_]
  not container.readinessProbe
  msg := sprintf("Container '%v' in Deployment '%v' does not have a readinessProbe configured.", [container.name, input.metadata.name])
}

# Deny Deployments using the default ServiceAccount (Least Privilege RBAC)
deny contains msg if {
  input.kind == "Deployment"
  not input.spec.template.spec.serviceAccountName
  msg := sprintf("Deployment '%v' does not define an explicit serviceAccountName. Running under the 'default' ServiceAccount is prohibited.", [input.metadata.name])
}

deny contains msg if {
  input.kind == "Deployment"
  input.spec.template.spec.serviceAccountName == "default"
  msg := sprintf("Deployment '%v' uses the 'default' ServiceAccount. Dedicated least-privilege ServiceAccounts are required.", [input.metadata.name])
}
