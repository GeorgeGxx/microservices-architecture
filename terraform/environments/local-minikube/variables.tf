variable "kubeconfig_path" {
  type        = string
  description = "Path to the local kubeconfig file"
  default     = "~/.kube/config"
}

variable "kube_context" {
  type        = string
  description = "Kubernetes context to target (minikube)"
  default     = "minikube"
}

variable "harbor_admin_password" {
  type        = string
  description = "Initial admin password for Harbor registry"
  default     = "Harbor12345"
  sensitive   = true
}

variable "argocd_admin_password" {
  type        = string
  description = "Initial admin password for ArgoCD"
  default     = "ArgoCD12345"
  sensitive   = true
}

variable "grafana_admin_password" {
  type        = string
  description = "Initial admin password for Grafana"
  default     = "Admin12345"
  sensitive   = true
}
