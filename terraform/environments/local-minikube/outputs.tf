output "harbor_url" {
  description = "Harbor Registry Web UI and Docker Registry URL"
  value       = "http://harbor.local:30002"
}

output "argocd_url" {
  description = "ArgoCD Web UI URL"
  value       = "http://localhost:30088"
}

output "grafana_url" {
  description = "Grafana Observability Dashboard URL"
  value       = "http://localhost:30030"
}

output "minikube_setup_instructions" {
  description = "Helpful instructions to access NodePorts and configure local Docker"
  sensitive   = true
  value       = <<EOT
================================================================================
MINIKUBE DEVSECOPS STACK READY
================================================================================
1. To access NodePort services directly on Windows without port forward:
   Run in an admin PowerShell: minikube service list

2. To authenticate Docker to local insecure Harbor:
   Add to Docker Desktop 'insecure-registries': ["harbor.local:30002", "localhost:30002", "10.0.0.0/8"]
   Add '127.0.0.1 harbor.local' to C:\Windows\System32\drivers\etc\hosts
   docker login harbor.local:30002 -u admin -p ${var.harbor_admin_password}

3. ArgoCD credentials:
   Username: admin
   Password: ${var.argocd_admin_password}
================================================================================
EOT
}
