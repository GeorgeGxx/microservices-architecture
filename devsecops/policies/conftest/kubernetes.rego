package main

import rego.v1

# Expose PodSpecs for supported Kubernetes workload controllers.
workload_pod_spec := input.spec.template.spec if {
  input.kind in {"Deployment", "StatefulSet", "DaemonSet", "Job"}
}

workload_pod_spec := input.spec.jobTemplate.spec.template.spec if {
  input.kind == "CronJob"
}

workload_containers contains container if {
  pod_spec := workload_pod_spec
  container := pod_spec.containers[_]
}

workload_containers contains container if {
  pod_spec := workload_pod_spec
  container := pod_spec.initContainers[_]
}

# Deny privileged workloads, including init containers.
deny contains msg if {
  container := workload_containers[_]
  container.securityContext.privileged == true
  msg := sprintf("Container '%v' in %v '%v' is privileged; privileged containers are prohibited.", [container.name, input.kind, input.metadata.name])
}

# Require both CPU and memory limits, rather than accepting an incomplete limit block.
deny contains msg if {
  container := workload_containers[_]
  not container.resources.limits.cpu
  msg := sprintf("Container '%v' in %v '%v' must specify a CPU limit.", [container.name, input.kind, input.metadata.name])
}

deny contains msg if {
  container := workload_containers[_]
  not container.resources.limits.memory
  msg := sprintf("Container '%v' in %v '%v' must specify a memory limit.", [container.name, input.kind, input.metadata.name])
}

# Accept digest references or versioned tags; reject untagged and latest-style refs.
deny contains msg if {
  container := workload_containers[_]
  image_ref := split(container.image, "/")[count(split(container.image, "/")) - 1]
  not contains(image_ref, "@sha256:")
  not contains(image_ref, ":")
  msg := sprintf("Container '%v' in %v '%v' uses an untagged image reference.", [container.name, input.kind, input.metadata.name])
}

deny contains msg if {
  container := workload_containers[_]
  image_ref := split(container.image, "/")[count(split(container.image, "/")) - 1]
  not contains(image_ref, "@sha256:")
  endswith(image_ref, ":latest")
  msg := sprintf("Container '%v' in %v '%v' uses a mutable latest image tag.", [container.name, input.kind, input.metadata.name])
}

deny contains msg if {
  container := workload_containers[_]
  image_ref := split(container.image, "/")[count(split(container.image, "/")) - 1]
  not contains(image_ref, "@sha256:")
  endswith(image_ref, "-latest")
  msg := sprintf("Container '%v' in %v '%v' uses a mutable latest-style image tag.", [container.name, input.kind, input.metadata.name])
}

# Warn on health checks across every supported workload type.
warn contains msg if {
  container := workload_containers[_]
  not container.livenessProbe
  msg := sprintf("Container '%v' in %v '%v' has no livenessProbe.", [container.name, input.kind, input.metadata.name])
}

warn contains msg if {
  container := workload_containers[_]
  not container.readinessProbe
  msg := sprintf("Container '%v' in %v '%v' has no readinessProbe.", [container.name, input.kind, input.metadata.name])
}

# Require a dedicated non-default ServiceAccount for each workload.
deny contains msg if {
  pod_spec := workload_pod_spec
  not pod_spec.serviceAccountName
  msg := sprintf("%v '%v' does not define an explicit serviceAccountName.", [input.kind, input.metadata.name])
}

deny contains msg if {
  pod_spec := workload_pod_spec
  pod_spec.serviceAccountName == "default"
  msg := sprintf("%v '%v' uses the default ServiceAccount.", [input.kind, input.metadata.name])
}
