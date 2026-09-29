# ==============================================================================
# Namespaces
# ==============================================================================
resource "kubernetes_namespace" "namespaces" {
  for_each = toset([
    "gatekeeper-system",
    "argocd",
    "observability",
    "opencost",
    "auth",
    "data",
    "vault",
    "keda",
    "dev"
  ])

  metadata {
    name = each.key
    labels = each.key == "dev" ? {
      "istio-injection" = "enabled"
      "environment"     = "dev"
      } : {
      "environment" = each.key
    }
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
  version    = "3.23.0"
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
  version    = "10.9.2"
  namespace  = "argocd"
  timeout    = 600

  set_sensitive {
    name  = "configs.secret.argocdServerAdminPassword"
    value = var.argocd_admin_password_hash
  }

  set {
    name  = "configs.secret.argocdServerAdminPasswordMtime"
    value = var.argocd_admin_password_mtime
  }

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
    value = "false"
  }
  set {
    name  = "configs.params.server\\.insecure"
    value = "false"
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
  # Fast reconciliation (poll Git every 15s without jitter for rapid dev sync)
  set {
    name  = "configs.cm.timeout\\.reconciliation"
    value = "15s"
  }
  set {
    name  = "configs.cm.timeout\\.reconciliation\\.jitter"
    value = "0s"
  }
  set {
    name  = "configs.params.reposerver\\.default\\.cache\\.expiration"
    value = "15s"
  }
  set {
    name  = "configs.params.controller\\.app\\.state\\.cache\\.expiration"
    value = "15s"
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
  version    = "89.2.2"
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
  set {
    name  = "grafana.sidecar.datasources.defaultDatasourceEnabled"
    value = "false"
  }
  set {
    name  = "grafana.env.GF_PLUGINS_PREINSTALL_AUTO_UPDATE"
    value = "false"
  }
  set {
    name  = "grafana.env.GF_PLUGINS_PREINSTALL_DISABLED"
    value = "true"
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
  # Disable non-exposed host components in Minikube to keep all Prometheus targets green
  set {
    name  = "kubeControllerManager.enabled"
    value = "false"
  }
  set {
    name  = "kubeScheduler.enabled"
    value = "false"
  }
  set {
    name  = "kubeEtcd.enabled"
    value = "false"
  }
  set {
    name  = "kubeProxy.enabled"
    value = "false"
  }
  # Enable discovery of ServiceMonitors across all namespaces (including staging)
  set {
    name  = "prometheus.prometheusSpec.serviceMonitorSelectorNilUsesHelmValues"
    value = "false"
  }
  set {
    name  = "prometheus.prometheusSpec.podMonitorSelectorNilUsesHelmValues"
    value = "false"
  }
}

# ==============================================================================
# 5. KEDA (Kubernetes Event-driven Autoscaling) v2.20.1
# ==============================================================================
resource "helm_release" "keda" {
  depends_on = [kubernetes_namespace.namespaces]

  name       = "keda"
  repository = "https://kedacore.github.io/charts"
  chart      = "keda"
  version    = "2.20.1"
  namespace  = "keda"
  timeout    = 600

  set {
    name  = "operator.resources.requests.cpu"
    value = "100m"
  }
  set {
    name  = "operator.resources.requests.memory"
    value = "128Mi"
  }
  set {
    name  = "operator.resources.limits.cpu"
    value = "500m"
  }
  set {
    name  = "operator.resources.limits.memory"
    value = "256Mi"
  }
  set {
    name  = "metricsServer.resources.requests.cpu"
    value = "100m"
  }
  set {
    name  = "metricsServer.resources.requests.memory"
    value = "128Mi"
  }
  set {
    name  = "metricsServer.resources.limits.cpu"
    value = "500m"
  }
  set {
    name  = "metricsServer.resources.limits.memory"
    value = "256Mi"
  }
}
