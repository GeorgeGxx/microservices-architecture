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

# Deny untagged containers and mutable latest-style tags (latest,
# staging-latest, prod-latest). Digest-pinned images are allowed.
deny contains msg if {
  input.kind == "Deployment"
  container := input.spec.template.spec.containers[_]
  image_ref := split(container.image, "/")[count(split(container.image, "/")) - 1]
  not contains(image_ref, "@sha256:")
  not contains(image_ref, ":")
  msg := sprintf("Container '%v' in Deployment '%v' uses an untagged image reference. Pin an immutable version or digest.", [container.name, input.metadata.name])
}

deny contains msg if {
  input.kind == "Deployment"
  container := input.spec.template.spec.containers[_]
  image_ref := split(container.image, "/")[count(split(container.image, "/")) - 1]
  not contains(image_ref, "@sha256:")
  endswith(image_ref, ":latest")
  msg := sprintf("Container '%v' in Deployment '%v' uses a mutable latest-style image reference. Pin an immutable version or digest.", [container.name, input.metadata.name])
}

deny contains msg if {
  input.kind == "Deployment"
  container := input.spec.template.spec.containers[_]
  image_ref := split(container.image, "/")[count(split(container.image, "/")) - 1]
  not contains(image_ref, "@sha256:")
  endswith(image_ref, "-latest")
  msg := sprintf("Container '%v' in Deployment '%v' uses an untagged or mutable latest-style image reference. Pin an immutable version or digest.", [container.name, input.metadata.name])
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
