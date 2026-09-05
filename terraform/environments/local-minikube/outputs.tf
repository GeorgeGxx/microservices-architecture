output "argocd_url" {
  description = "ArgoCD Web UI URL"
  value       = "https://localhost:30088"
}

output "grafana_url" {
  description = "Grafana Observability Dashboard URL"
  value       = "http://localhost:30030"
}

output "minikube_setup_instructions" {
  description = "Helpful instructions to access local DevSecOps platform"
  sensitive   = true
  value       = <<EOT
================================================================================
MINIKUBE DEVSECOPS STACK READY
================================================================================
1. All container images are pulled directly from Docker Hub (georgegxx/*).
   No local insecure registry required.

3. ArgoCD credentials:
   Username: admin
   Password: ${var.argocd_admin_password}
================================================================================
EOT
}
