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

variable "grafana_admin_password" {
  type        = string
  description = "Initial admin password for Grafana"
  default     = "admin"
  sensitive   = true
}

variable "argocd_admin_password" {
  type        = string
  description = "Initial admin password for ArgoCD"
  default     = "admin"
  sensitive   = true
}

variable "argocd_admin_password_hash" {
  type        = string
  description = "Fixed bcrypt hash for the ArgoCD admin password (corresponds to the plaintext 'admin')"
  default     = "$2b$12$ml7DXUbuMyVopVR2bqiysOgmp68iCknXy3kdhw.LiSEjK.a0p2elu"
  sensitive   = true
}

variable "argocd_admin_password_mtime" {
  type        = string
  description = "Fixed timestamp; do not touch unless you change the password."
  default     = "2026-01-01T00:00:00Z"
}