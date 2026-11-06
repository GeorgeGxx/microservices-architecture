# Enterprise Platform Version & Compatibility Matrix

This matrix serves as the single source of truth for pinned versions across all runtimes, GitOps control planes, DevSecOps scanners, infrastructure providers, and observability components.

## 1. GitOps, Kubernetes & Service Mesh Control Plane

| Component | Pinned Version | Helm Chart / Artifact | Target Environments | Verification Status |
|---|---|---|---|---|
| **Argo CD Application Version** | **`v3.6.1`** | `quay.io/argoproj/argocd:v3.6.1` | Minikube, AWS EKS (DP1 & DP2) | Verified (`helm template` + `conftest`) |
| **Argo CD Helm Chart** | **`10.14.0`** | `argo/argo-cd` | Minikube (`main.tf`), AWS EKS (`argocd-prod.yaml`) | Verified |
| **Helm CLI** | **`v4.3.1`** | `scripts/install-helm4.sh` | GitHub Actions, Azure DevOps, Bitbucket Pipelines | Verified |
| **OPA Gatekeeper** | **`v3.23.0`** | `gatekeeper/gatekeeper` | Minikube, EKS, AKS, GKE | Verified |
| **Istio Service Mesh (Ambient)** | **`v1.31.3`** | `istio/base`, `istiod`, `ztunnel` | Minikube, EKS, AKS, GKE | Verified |
| **KEDA Autoscaler** | **`v2.21.0`** | `kedacore/keda` | Minikube, EKS, AKS, GKE | Verified |

---

## 2. DevSecOps & Software Supply Chain Security Stack

| Tool | Pinned Version | Primary Responsibility | Configuration / Policy Path | CI/CD Enforcement |
|---|---|---|---|---|
| **Semgrep** | **`1.110.0`** | Static Application Security Testing (SAST) | `devsecops/sast/semgrep/semgrep-rules.yaml` | GitHub Actions, Azure DevOps, Bitbucket Pipelines |
| **Trivy** | **`v0.76.1`** | Container, FS, Dependency, IaC & CycloneDX SBOM | `devsecops/compliance/trivy/trivy.yaml` | GitHub Actions, Azure DevOps, Bitbucket Pipelines |
| **Gitleaks** | **`v8.24.2`** | Secrets Detection | `devsecops/sast/gitleaks/.gitleaks.toml` | GitHub Actions, Azure DevOps, Bitbucket Pipelines |
| **Conftest (OPA)** | **`v0.58.0`** | Pre-flight Kubernetes/Helm Rego Policy Gate | `devsecops/policies/conftest/kubernetes.rego` | GitHub Actions, Azure DevOps, Bitbucket Pipelines |
| **Sigstore Cosign** | **`v3.1.3`** | OCI Image Signing by Digest & Provenance Verification | `devsecops/compliance/cosign/cosign.pub` | GitHub Actions, Azure DevOps, Bitbucket Pipelines |
| **SonarQube Cloud** | **`5.2.0.4988` / `npx`** | Code Quality, Coverage & Security Hotspots | Workflow & pipeline scanner steps | GitHub Actions, Azure DevOps, Bitbucket Pipelines |

---

## 3. Application Runtimes & Frameworks

| Workload | Language / Runtime | Framework | Base Container Image | Port |
|---|---|---|---|---|
| `frontend` | TypeScript / Node.js `24-alpine` | React `19` / Vite | `nginxinc/nginx-unprivileged:1.27-alpine` | `8080` |
| `cosmo-router` | Go | WunderGraph Cosmo Router `v0.362.0` | `ghcr.io/wundergraph/cosmo/router:0.362.0` | `8080` |
| `products-service` | Java `21` (Temurin) | Spring Boot `4.1.0` | `eclipse-temurin:21-jre-alpine` | `8004` |
| `orders-service` | Java `21` (Temurin) | Spring Boot `4.1.0` | `eclipse-temurin:21-jre-alpine` | `8003` |
| `inventory-service` | Java `21` (Temurin) | Spring Boot `4.1.0` | `eclipse-temurin:21-jre-alpine` | `8001` |
| `notification-service` | Java `21` (Temurin) | Spring Boot `4.1.0` | `eclipse-temurin:21-jre-alpine` | `8002` |
| `payments-service` | Go `1.26` | Gin `v1.12.0` / GORM | `gcr.io/distroless/static-debian12:nonroot` | `8085` |
| `fulfillment-service` | TypeScript / Node.js `24-alpine` | NestJS `12.2.0` / TypeORM | `node:24-alpine` | `8086` |
| `analytics-service` | Python `3.12` | FastAPI `0.160.0` / SQLAlchemy `2.0` | `python:3.12-slim` | `8087` |
| `demand-forecast` | Python `3.12` | FastAPI `0.160.0` / Scikit-Learn | `python:3.12-slim` | `8005` |
| `mlops-training` | Python `3.12` / Java `21` | PySpark `4.2.0` / MLflow `3.17.2` | `python:3.12-slim` | Batch |
| `backstage-idp` | TypeScript / Node.js `24` | Backstage `1.56.3` | `ghcr.io/backstage/backstage:1.56.3` | `7007` |

---

## 4. Infrastructure-as-Code & Observability Stack

| Component | Pinned Version | Notes |
|---|---|---|
| **Terraform Core** | `>= 1.6.0` (CI `1.16.2`) | AWS (`eks` + `eks_dp2`), Azure (`aks` + `aks_dp2`), GCP (`gke` + `gke_dp2`), `local-minikube` |
| **kube-prometheus-stack** | `89.2.2` | Prometheus `v3.14.0`, Grafana `13.2.3`, Alertmanager |
| **Grafana Loki / Tempo / Alloy** | `3.7.8` / `3.0.5` / `v1.21.0` | Unified LGTM telemetry pipeline |
| **OpenTelemetry Collector** | `0.159.0` | OTLP gRPC (`4317`) and HTTP (`4318`) |
| **Prometheus Blackbox Exporter** | `v0.29.0` | Synthetic endpoint probing |
| **Keycloak IAM** | `26.8.1` | Enterprise OIDC SSO (`microservices-realm`) |
| **PostgreSQL / Redis / Kafka** | `18` / `8.8.1` / `Confluent 8.3.2` | Stateful data & messaging layer |
