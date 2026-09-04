package main

# Deny containers running in privileged mode
deny[msg] {
  input.kind == "Deployment"
  container := input.spec.template.spec.containers[_]
  container.securityContext.privileged == true
  msg := sprintf("Container '%v' in Deployment '%v' is running in privileged mode. Privileged containers are not allowed.", [container.name, input.metadata.name])
}

# Deny containers without memory/cpu limits
deny[msg] {
  input.kind == "Deployment"
  container := input.spec.template.spec.containers[_]
  not container.resources.limits
  msg := sprintf("Container '%v' in Deployment '%v' must specify resource limits (cpu & memory).", [container.name, input.metadata.name])
}

# Deny containers using 'latest' tag in image
deny[msg] {
  input.kind == "Deployment"
  container := input.spec.template.spec.containers[_]
  endswith(container.image, ":latest")
  msg := sprintf("Container '%v' in Deployment '%v' uses the 'latest' image tag. Pin a specific SHA or version tag.", [container.name, input.metadata.name])
}

# Warn if liveness probe is missing on Deployment containers
warn[msg] {
  input.kind == "Deployment"
  container := input.spec.template.spec.containers[_]
  not container.livenessProbe
  msg := sprintf("Container '%v' in Deployment '%v' does not have a livenessProbe configured.", [container.name, input.metadata.name])
}

# Warn if readiness probe is missing on Deployment containers
warn[msg] {
  input.kind == "Deployment"
  container := input.spec.template.spec.containers[_]
  not container.readinessProbe
  msg := sprintf("Container '%v' in Deployment '%v' does not have a readinessProbe configured.", [container.name, input.metadata.name])
}
