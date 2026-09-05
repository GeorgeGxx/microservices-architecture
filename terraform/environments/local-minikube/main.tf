# ==============================================================================
# Namespaces
# ==============================================================================
resource "kubernetes_namespace" "namespaces" {
  for_each = toset([
    "harbor",
    "gatekeeper-system",
    "argocd",
    "observability",
    "staging",
    "prod"
  ])

  metadata {
    name = each.key
    labels = contains(["staging", "prod"], each.key) ? {
      "istio-injection" = "enabled"
      "environment"     = each.key
    } : {
      "environment" = each.key
    }
  }
}

# ==============================================================================
# 1. Harbor Container Registry (HTTP Insecure, NodePort 30002)
# ==============================================================================
resource "helm_release" "harbor" {
  depends_on = [kubernetes_namespace.namespaces]

  name       = "harbor"
  repository = "https://helm.goharbor.io"
  chart      = "harbor"
  version    = "1.14.2"
  namespace  = "harbor"
  timeout    = 600

  set {
    name  = "expose.type"
    value = "nodePort"
  }
  set {
    name  = "expose.tls.enabled"
    value = "false"
  }
  set {
    name  = "expose.nodePort.ports.http.nodePort"
    value = "30002"
  }
  set {
    name  = "externalURL"
    value = "http://harbor.local:30002"
  }
  set {
    name  = "harborAdminPassword"
    value = var.harbor_admin_password
  }
  # Disable built-in Trivy scanner inside Harbor to conserve RAM (Trivy runs in CI pipeline)
  set {
    name  = "trivy.enabled"
    value = "false"
  }
  # Light resource limits for local minikube budget
  set {
    name  = "core.resources.requests.cpu"
    value = "100m"
  }
  set {
    name  = "core.resources.requests.memory"
    value = "128Mi"
  }
  set {
    name  = "core.resources.limits.cpu"
    value = "500m"
  }
  set {
    name  = "core.resources.limits.memory"
    value = "512Mi"
  }
}

# ==============================================================================
# 2. Gatekeeper (OPA Admission Controller)
# ==============================================================================
resource "helm_release" "gatekeeper" {
  depends_on = [kubernetes_namespace.namespaces]

  name       = "gatekeeper"
  repository = "https://open-policy-agent.github.io/gatekeeper/charts"
  chart      = "gatekeeper"
  version    = "3.16.0"
  namespace  = "gatekeeper-system"
  timeout    = 600

  set {
    name  = "controllerManager.resources.requests.cpu"
    value = "100m"
  }
  set {
    name  = "controllerManager.resources.requests.memory"
    value = "256Mi"
  }
  set {
    name  = "controllerManager.resources.limits.cpu"
    value = "500m"
  }
  set {
    name  = "controllerManager.resources.limits.memory"
    value = "512Mi"
  }
  set {
    name  = "audit.resources.requests.cpu"
    value = "100m"
  }
  set {
    name  = "audit.resources.requests.memory"
    value = "128Mi"
  }
}

# ==============================================================================
# 3. ArgoCD (GitOps Engine)
# ==============================================================================
resource "helm_release" "argocd" {
  depends_on = [kubernetes_namespace.namespaces]

  name       = "argocd"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  version    = "6.7.18"
  namespace  = "argocd"
  timeout    = 600

  set {
    name  = "server.service.type"
    value = "NodePort"
  }
  set {
    name  = "server.service.nodePortHttp"
    value = "30088"
  }
  set {
    name  = "server.insecure"
    value = "true"
  }
  set {
    name  = "server.resources.requests.cpu"
    value = "100m"
  }
  set {
    name  = "server.resources.requests.memory"
    value = "128Mi"
  }
  set {
    name  = "server.resources.limits.cpu"
    value = "500m"
  }
  set {
    name  = "server.resources.limits.memory"
    value = "512Mi"
  }
  set {
    name  = "repoServer.resources.requests.memory"
    value = "128Mi"
  }
  set {
    name  = "applicationController.resources.requests.memory"
    value = "128Mi"
  }
}

# ==============================================================================
# 4. Observability: Prometheus & Grafana (kube-prometheus-stack)
# ==============================================================================
resource "helm_release" "observability" {
  depends_on = [kubernetes_namespace.namespaces]

  name       = "kube-prometheus"
  repository = "https://prometheus-community.github.io/helm-charts"
  chart      = "kube-prometheus-stack"
  version    = "58.2.2"
  namespace  = "observability"
  timeout    = 900

  set {
    name  = "grafana.adminPassword"
    value = var.grafana_admin_password
  }
  set {
    name  = "grafana.service.type"
    value = "NodePort"
  }
  set {
    name  = "grafana.service.nodePort"
    value = "30030"
  }
  # Optimized retention to save Minikube disk and RAM
  set {
    name  = "prometheus.prometheusSpec.retention"
    value = "2d"
  }
  set {
    name  = "prometheus.prometheusSpec.resources.requests.cpu"
    value = "200m"
  }
  set {
    name  = "prometheus.prometheusSpec.resources.requests.memory"
    value = "512Mi"
  }
  set {
    name  = "prometheus.prometheusSpec.resources.limits.cpu"
    value = "1000m"
  }
  set {
    name  = "prometheus.prometheusSpec.resources.limits.memory"
    value = "1536Mi"
  }
}
