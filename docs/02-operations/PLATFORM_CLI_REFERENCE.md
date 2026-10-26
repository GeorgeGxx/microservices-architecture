# Platform CLI Reference

> [!TIP]
> [Enterprise Platform Hub](../../README.md) > **02. Operations** > [Platform CLI Reference](./PLATFORM_CLI_REFERENCE.md)

> [!IMPORTANT]
> **Single Source of Truth (SSOT):** This document is the canonical, centralized reference for all operational commands and options for [`platform-minikube.ps1`](../../platform-minikube.ps1) and [`platform-multicloud.ps1`](../../platform-multicloud.ps1). To eliminate documentation redundancy across the repository, all other operational guides link directly here for CLI syntax and workflow examples.

All platform PowerShell scripts (`*.ps1`) are standardized on **PowerShell 7+ (`pwsh`)** with `#Requires -Version 7.0` and cross-platform shebangs `#!/usr/bin/env pwsh`. Legacy Windows PowerShell 5.1 (`powershell.exe`) is intentionally blocked by `#Requires` to ensure deterministic UTF-8 encoding, modern parameter splatting, and complete cross-platform parity between Windows, macOS, Linux, and CI/CD runners.

---

## 🏛️ Architecture & Entrypoint Separation

The platform provides two independent, non-cascading PowerShell entrypoints designed for distinct operational scopes:

| Entrypoint | Target Infrastructure | Primary Use Case | Cloud & Container Runtime | CI/CD & Delivery Engine |
| :--- | :--- | :--- | :--- | :--- |
| [`platform-minikube.ps1`](../../platform-minikube.ps1) | `dev` (Local) | Zero-cloud-cost local development, fast reload, MLOps, Vault, Canary, and full DevSecOps shift-left gates | Minikube (containerd) | GitHub Actions CI + ArgoCD GitOps |
| [`platform-multicloud.ps1`](../../platform-multicloud.ps1) | `dev`, `staging`, `prod` | Multi-cloud Terraform lifecycle, Gatekeeper governance, atomic rollback, and endpoint verification across AWS, Azure, and GCP | AWS EKS, Azure AKS, GCP GKE | AWS ArgoCD, Azure DevOps, Bitbucket Pipelines |

---

## 🚀 Quick Syntax Summary

```powershell
# Local Minikube CLI
.\platform-minikube.ps1 <command> [options]

# Multi-Cloud Orchestrator CLI
.\platform-multicloud.ps1 <command> -Provider <aws|azure|gcp> -Environment <dev|staging|prod> [options]
```

---

## 💻 Part I: Local Platform Orchestrator (`platform-minikube.ps1`)

[`platform-minikube.ps1`](../../platform-minikube.ps1) encapsulates all local developer workflows, container builds, port-forward supervisors, and local test runners.

### 1. Cluster Lifecycle & Fast Resume

```powershell
# Full initial platform bootstrap (Terraform, Istio, Gatekeeper, Helm, Keycloak, Cosmo Router)
.\platform-minikube.ps1 up

# Lightweight native Kubernetes mode (bypasses Istio mTLS and Kiali to minimize RAM consumption)
.\platform-minikube.ps1 up -WithoutIstio

# Bootstrap with automated container compilation from Dockerfiles
.\platform-minikube.ps1 up -Build

# Bootstrap with isolated canary release active on products-service
.\platform-minikube.ps1 up -DeployCanary -CanaryImageTag "v2.1"

# Fast platform resume (< 30s) bypassing Terraform, Gatekeeper, Helm package rebuild, and FinOps audits
.\platform-minikube.ps1 start                            # Resumes cluster VM, pods & tunnels
.\platform-minikube.ps1 start -WithoutIstio              # Fast resume in lightweight native K8s mode
.\platform-minikube.ps1 start -DeployCanary -CanaryImageTag "v2.1" # Fast resume with canary
.\platform-minikube.ps1 up -Fast                         # Equivalent alias for start

# Safe cluster pause (preserves Postgres databases, PVCs, MLflow artifacts, and cluster state)
.\platform-minikube.ps1 down

# Complete cluster purge (safely stops tunnels, purges Minikube VM, disk volumes, and cached state)
.\platform-minikube.ps1 down -Destroy
.\platform-minikube.ps1 destroy
```

### 2. Container Builds, Service Targeting & Registry Push

```powershell
# Compile all microservices and frontend from source and load directly into Minikube
.\platform-minikube.ps1 build

# Fast targeted compilation: rebuild, load into containerd, and restart only a single service
.\platform-minikube.ps1 build -Service orders-service
.\platform-minikube.ps1 build -Service frontend
.\platform-minikube.ps1 build -Service products-service

# Include MLOps stack container images (demand-forecast, mlops-training, mlflow)
.\platform-minikube.ps1 build -IncludeMlops

# Build and push directly to Docker Hub registry (georgegxx/*) with automatic retry backoff
.\platform-minikube.ps1 build -IncludeMlops -Push -ImageTag 1.1.0

# Push existing local container images to Docker Hub without rebuilding source code
.\platform-minikube.ps1 build -PushOnly -ImageTag 1.0.0
.\platform-minikube.ps1 build -PushOnly -Service orders-service -ImageTag 1.0.0
```

### 3. Declarative Tag Synchronization (`set-tag`)

The `set-tag` command uses `yq` to update container image tags across Helm values manifests while strictly protecting third-party infrastructure components (Cosmo Router, Kiali, Prometheus, Keycloak) from accidental mutation.

```powershell
# Synchronize application image tags in local Minikube values (helm/values/values-minikube.yaml)
.\platform-minikube.ps1 set-tag -ImageTag "1.1.0"

# Target a specific microservice only (leaving other service tags untouched)
.\platform-minikube.ps1 set-tag -ImageTag "1.1.0" -Service orders-service

# Synchronize tags globally across all Helm values environments (minikube, EKS, AKS, GKE)
.\platform-minikube.ps1 set-tag -ImageTag "1.1.0" -TargetEnv all
```

### 4. DevSecOps Quality, Testing & DAST Gates

```powershell
# Execute Java 21 + Maven multi-module reactor unit test suite
.\platform-minikube.ps1 test

# Run 5 Shift-Left security gates (Gitleaks, TFLint, Trivy, Conftest OPA, Cosign)
.\platform-minikube.ps1 security-scan

# Execute Newman API contract integration tests (23/23 assertions against live router)
.\platform-minikube.ps1 contract

# Run Grafana k6 performance, throughput, and latency SLO benchmark suite
.\platform-minikube.ps1 performance

# Run OWASP ZAP baseline dynamic application security scan (DAST) against live frontend
.\platform-minikube.ps1 dast

# Run Business Continuity & Disaster Recovery (BCDR) backup and restore drill
.\platform-minikube.ps1 bcdr
```

### 5. Progressive Delivery & Canary Testing

```powershell
# Adjust traffic split dynamically between v1 (stable) and v2 (canary)
.\platform-minikube.ps1 canary -Action weight -V1Weight 80 -V2Weight 20

# Execute automated step-by-step progressive canary rollout (10% -> 25% -> 50% -> 75% -> 100%)
.\platform-minikube.ps1 canary -Action rollout -Steps 10,25,50,75,100 -StepIntervalSeconds 30

# Promote canary v2 to stable baseline
.\platform-minikube.ps1 canary -Action promote

# Retire canary deployment after GitOps values writeback has stabilized
.\platform-minikube.ps1 canary -Action retire
```

### 6. Security, Identity & Secret Management

```powershell
# Audit HashiCorp Vault operational status and unseal health
.\platform-minikube.ps1 vault -VaultAction status

# Configure Vault Kubernetes authentication engine and service account roles
.\platform-minikube.ps1 vault -VaultAction k8s-auth

# Bootstrap Vault PKI engine and issue mTLS intermediate certificates for Istio
.\platform-minikube.ps1 vault -VaultAction istio-pki -RotateVaultPki

# Generate zero-trust cryptographically secure secrets in the target namespace
.\platform-minikube.ps1 secrets -Environment dev
```

### 7. MLOps Pipeline & MLflow Stack

```powershell
# Deploy/refresh MLflow tracking server, PySpark sales-capture, forecast API, and training
.\platform-minikube.ps1 mlops
```

### 8. Observability, Networking & FinOps

```powershell
# Display active local port-forward URLs, service endpoints, and credentials table
.\platform-minikube.ps1 urls

# Launch background tunnel supervisor for local port-forwarding
.\platform-minikube.ps1 tunnels

# Start or inspect Cloudflare Anycast Quick Tunnels for external zero-trust ingress
.\platform-minikube.ps1 cloudflare -Action start
.\platform-minikube.ps1 cloudflare -Action status
.\platform-minikube.ps1 cloudflare -Action stop

# Run comprehensive deep cluster diagnostics across namespaces, pods, and metrics
.\platform-minikube.ps1 doctor

# Query live Kubernetes workload cost allocations via kubectl-cost and OpenCost
.\platform-minikube.ps1 cost

# Run offline FinOps architecture cost model estimation
.\platform-minikube.ps1 finops -Environment minikube
.\platform-minikube.ps1 finops -Environment staging
.\platform-minikube.ps1 finops -Environment prod

# Audit or install required Windows host CLI dependencies via WinGet
.\platform-minikube.ps1 tools
.\platform-minikube.ps1 tools -Install

# Compose Cosmo Router GraphQL Federation v2 execution schema
.\platform-minikube.ps1 compose-router

# Generate visual Graphviz architecture dependency model
.\platform-minikube.ps1 graph

# Synchronize all 16 architecture blueprint tabs into docs/Diagrams.drawio
.\platform-minikube.ps1 diagrams
```

---

## ☁️ Part II: Multi-Cloud Enterprise Orchestrator (`platform-multicloud.ps1`)

[`platform-multicloud.ps1`](../../platform-multicloud.ps1) provides an enterprise multi-cloud operational control plane for AWS, Azure, and GCP.

### 1. Pre-Deploy Shift-Left Security Gate

Runs Gitleaks secret detection, TFLint, Trivy IaC misconfiguration scan, Conftest OPA policy audit, and optional Cosign container image signature verification before any cloud provisioning.

```powershell
# Run pre-deploy static security scans for AWS
.\platform-multicloud.ps1 pre-deploy -Provider aws -Environment staging

# Run pre-deploy static security scans with Graphviz architecture modeling
.\platform-multicloud.ps1 pre-deploy -Provider azure -Environment prod -GenerateGraph

# Run pre-deploy static security scans for GCP
.\platform-multicloud.ps1 pre-deploy -Provider gcp -Environment dev
```

### 2. Infrastructure Lifecycle Management (Terraform)

```powershell
# Formats, validates, and generates a deterministic binary plan artifact (.tfplan)
.\platform-multicloud.ps1 plan -Provider aws -Environment staging -Flavor eks
.\platform-multicloud.ps1 plan -Provider aws -Environment staging -Flavor ecs-fargate
.\platform-multicloud.ps1 plan -Provider azure -Environment prod -DataPlane all
.\platform-multicloud.ps1 plan -Provider gcp -Environment staging

# Applies the verified binary plan artifact with production safeguards
.\platform-multicloud.ps1 apply -Provider aws -Environment staging -PlanFile .terraform/tfplan-staging.binary
.\platform-multicloud.ps1 apply -Provider azure -Environment prod -DataPlane primary
.\platform-multicloud.ps1 apply -Provider gcp -Environment staging -AutoApprove

# Audit live infrastructure drift against remote state (plan -refresh-only)
.\platform-multicloud.ps1 drift -Provider aws -Environment prod

# Display and export Terraform state outputs
.\platform-multicloud.ps1 output -Provider aws -Environment staging

# Forcibly release a stale Terraform remote state lock
.\platform-multicloud.ps1 unlock -Provider aws -Environment staging -LockId "15cd8b02-39c2-47df-8f52-..."

# Safely destroy cloud resources with interactive confirmation
.\platform-multicloud.ps1 destroy -Provider aws -Environment staging
.\platform-multicloud.ps1 destroy -Provider azure -Environment prod -DataPlane secondary
```

### 3. Workload Delivery & GitOps Reconciliation

```powershell
# Trigger Argo CD GitOps reconciliation on AWS EKS
.\platform-multicloud.ps1 sync-argocd -Provider aws -Environment staging

# Deploy the microservices Umbrella Helm chart directly to Azure AKS or GCP GKE
.\platform-multicloud.ps1 apply-workloads -Provider azure -Environment dev
.\platform-multicloud.ps1 apply-workloads -Provider gcp -Environment staging

# Execute immediate Helm atomic rollback to a previous revision
.\platform-multicloud.ps1 rollback -Provider azure -Environment dev -Revision 2
.\platform-multicloud.ps1 rollback -Provider gcp -Environment staging -Revision 1
```

### 4. Post-Deploy Dynamic Quality & DAST Gate

Executes smoke tests, authenticated Newman contract tests, k6 load benchmarks, and OWASP ZAP baseline DAST against the live deployed cloud endpoint.

```powershell
# Post-deployment validation on AWS EKS
.\platform-multicloud.ps1 post-deploy -Provider aws -Environment staging -TargetUrl "https://staging.domain.com" -KeycloakUrl "https://auth.staging.domain.com"

# Post-deployment validation on Azure AKS
.\platform-multicloud.ps1 post-deploy -Provider azure -Environment prod -TargetUrl "https://azure.domain.com" -KeycloakUrl "https://auth.azure.domain.com"

# Post-deployment validation on GCP GKE
.\platform-multicloud.ps1 post-deploy -Provider gcp -Environment dev -TargetUrl "https://gcp.domain.com" -KeycloakUrl "https://auth.gcp.domain.com"
```

### 5. End-to-End Orchestrated Pipeline

Executes the full automated release flow: `pre-deploy` -> `apply` -> delivery sync -> `post-deploy`.

```powershell
# End-to-end automated delivery on GCP
.\platform-multicloud.ps1 pipeline -Provider gcp -Environment dev -TargetUrl "https://gcp-dev.domain.com" -KeycloakUrl "https://auth.gcp-dev.domain.com"

# End-to-end automated delivery on Azure
.\platform-multicloud.ps1 pipeline -Provider azure -Environment dev -TargetUrl "https://azure-dev.domain.com" -KeycloakUrl "https://auth.azure-dev.domain.com"
```

### 6. OPA Gatekeeper Governance & Multi-Cloud Diagnostics

```powershell
# Audit live cluster compliance against OPA Gatekeeper constraints
.\platform-multicloud.ps1 gatekeeper -Provider aws -Environment staging -Action audit

# Deploy Gatekeeper ConstraintTemplates and Constraints
.\platform-multicloud.ps1 gatekeeper -Provider azure -Environment prod -Action deploy

# Test Gatekeeper admission rejection by attempting to deploy non-compliant pod
.\platform-multicloud.ps1 gatekeeper -Provider gcp -Environment dev -Action test

# Comprehensive multi-cloud diagnostic audit (credentials, Kubeconfig, nodes, Gatekeeper)
.\platform-multicloud.ps1 doctor -Provider aws
.\platform-multicloud.ps1 doctor -Provider azure
.\platform-multicloud.ps1 doctor -Provider gcp

# Display active cloud platform status and workload health
.\platform-multicloud.ps1 status -Provider aws -Environment staging
.\platform-multicloud.ps1 status -Provider azure -Environment prod -DataPlane all

# Audit and install cloud CLI toolchain dependencies via WinGet
.\platform-multicloud.ps1 tools -Provider aws
.\platform-multicloud.ps1 tools -Provider aws -Install
```

---

## 📋 Part III: Complete CLI Parameter Matrix

### Parameters for `platform-minikube.ps1`

| Parameter | Type | Default | Allowed Values | Description |
| :--- | :--- | :--- | :--- | :--- |
| `-Command` | `string` | `"help"` | `up`, `bootstrap`, `start`, `resume`, `down`, `stop`, `destroy`, `build`, `test`, `mlops`, `doctor`, `verify`, `status`, `cost`, `finops`, `tools`, `canary`, `vault`, `smoke`, `contract`, `performance`, `dast`, `tunnels`, `cloudflare`, `secrets`, `graph`, `security-scan`, `diagrams`, `bcdr`, `urls`, `set-tag`, `help` | The primary operational command to execute. |
| `-Environment` | `string` | `"dev"` | `dev`, `minikube`, `staging`, `prod` | Target environment namespace scope. |
| `-Build` | `switch` | `$false` | `$true`, `$false` | When passed to `up` or `start`, automatically compiles container images from source. |
| `-Service` | `string` | `"all"` | `all`, `orders-service`, `products-service`, `inventory-service`, `notification-service`, `frontend`, `demand-forecast`, `mlops-training`, `mlflow` | Target an individual microservice for `build` or `set-tag`. |
| `-IncludeMlops` | `switch` | `$false` | `$true`, `$false` | Includes MLOps images (`forecast`, `training`, `mlflow`) in `build`. |
| `-Push` | `switch` | `$false` | `$true`, `$false` | Pushes built container images to Docker Hub registry with exponential retry backoff. |
| `-PushOnly` | `switch` | `$false` | `$true`, `$false` | Skips compilation and pushes existing local container images to Docker Hub registry. |
| `-ImageTag` | `string` | `""` | Valid SemVer tag | Target container image tag to compile, push, or synchronize. |
| `-TargetEnv` | `string` | `"minikube"` | `minikube`, `all` | Target Helm values scope for `set-tag` (`minikube` only or all cloud profiles). |
| `-Fast` | `switch` | `$false` | `$true`, `$false` | Fast-resume mode (< 30s) bypassing Terraform, Gatekeeper, and Helm package rebuild. |
| `-WithIstio` | `switch` | `$true` | `$true`, `$false` | Enables Istio service mesh, mTLS, and Kiali observability during bootstrap. |
| `-WithoutIstio` | `switch` | `$false` | `$true`, `$false` | Enables lightweight Kubernetes native mode without service mesh sidecars. |
| `-DeployCanary` | `switch` | `$false` | `$true`, `$false` | Deploys isolated canary deployment alongside stable version. |
| `-CanaryImageTag`| `string` | `"canary"` | Valid tag string | Image tag to use for the canary deployment. |
| `-Action` | `string` | `""` | `weight`, `rollout`, `promote`, `retire`, `start`, `stop`, `status`, `restart` | Action to execute for `canary` or `cloudflare` commands. |
| `-V1Weight` | `int` | `90` | `0` to `100` | Traffic percentage allocated to stable v1 deployment. |
| `-V2Weight` | `int` | `10` | `0` to `100` | Traffic percentage allocated to canary v2 deployment. |
| `-Steps` | `int[]` | `@(10,25,50,75,100)` | Array of ints | Progressive percentage increments during canary rollout. |
| `-VaultAction` | `string` | `""` | `status`, `k8s-auth`, `istio-pki` | Action to execute for `vault` operations. |
| `-SkipScans` | `switch` | `$false` | `$true`, `$false` | Bypasses shift-left security scan gates during platform bootstrap. |
| `-Cpus` | `int` | `8` | Positive integer | CPU count allocated to the Minikube virtual machine. |
| `-MemoryMb` | `int` | `16384` | Positive integer | RAM in megabytes allocated to the Minikube virtual machine. |
| `-DiskSize` | `string` | `"40g"` | Valid disk string | Disk storage budget allocated to Minikube. |

### Parameters for `platform-multicloud.ps1`

| Parameter | Type | Default | Allowed Values | Description |
| :--- | :--- | :--- | :--- | :--- |
| `-Command` | `string` | `"help"` | `pre-deploy`, `plan`, `apply`, `destroy`, `drift`, `output`, `unlock`, `post-deploy`, `pipeline`, `sync-argocd`, `apply-workloads`, `rollback`, `gatekeeper`, `doctor`, `status`, `tools`, `security-scan`, `help` | The cloud operational command to execute. |
| `-Provider` | `string` | *(Mandatory)* | `aws`, `azure`, `gcp` | Target cloud service provider. |
| `-Environment` | `string` | `"dev"` | `dev`, `staging`, `prod` | Target cloud environment profile. |
| `-Flavor` | `string` | `"eks"` | `eks`, `ecs-fargate`, `ec2-compact` | Infrastructure compute flavor (AWS only). |
| `-DataPlane` | `string` | `"all"` | `all`, `primary`, `secondary` | Target cluster module in production multi-cluster deployments. |
| `-AutoApprove` | `switch` | `$false` | `$true`, `$false` | Bypasses interactive confirmation prompts for `apply` and `destroy`. |
| `-TargetUrl` | `string` | `""` | Valid URL | Base URL of deployed application ingress for `post-deploy` smoke, Newman, k6, and DAST checks. |
| `-KeycloakUrl` | `string` | `""` | Valid URL | Keycloak authentication endpoint for token-authorized API tests. |
| `-Revision` | `int` | `0` | Positive integer | Target Helm release revision for `rollback` command. |
| `-LockId` | `string` | `""` | Valid lock ID string | Remote state lock identifier to forcibly release with `unlock`. |
| `-Action` | `string` | `"audit"` | `audit`, `deploy`, `test`, `install` | Operational action for `gatekeeper` policy management. |
| `-GenerateGraph`| `switch` | `$false` | `$true`, `$false` | Generates a Graphviz visual architecture diagram during `pre-deploy`. |
| `-Install` | `switch` | `$false` | `$true`, `$false` | Automatically attempts to install missing CLI tools via WinGet during `tools`. |

---

## 🎯 Part IV: Recipes by Operational Persona

### 1. Daily Developer Workflow
```powershell
# 1. Start or resume local environment in under 30 seconds
.\platform-minikube.ps1 start

# 2. Modify code in orders-service, rebuild only orders-service, and reload into cluster
.\platform-minikube.ps1 build -Service orders-service

# 3. Verify health with smoke tests and inspect local endpoint URLs
.\platform-minikube.ps1 smoke
.\platform-minikube.ps1 urls

# 4. Safely pause cluster at the end of the day (zero state loss)
.\platform-minikube.ps1 down
```

### 2. Quality & Performance Engineer
```powershell
# 1. Run full unit and API contract test suite
.\platform-minikube.ps1 test
.\platform-minikube.ps1 contract

# 2. Execute k6 performance and latency SLO benchmarks
.\platform-minikube.ps1 performance

# 3. Run OWASP ZAP baseline dynamic application security scan
.\platform-minikube.ps1 dast
```

### 3. Release Manager & DevSecOps Engineer
```powershell
# 1. Verify shift-left security scans
.\platform-minikube.ps1 security-scan

# 2. Synchronize container image release tag across all Helm values manifests
.\platform-minikube.ps1 set-tag -ImageTag "1.2.0" -TargetEnv all

# 3. Progressive canary rollout on products-service
.\platform-minikube.ps1 canary -Action rollout -Steps 10,25,50,75,100 -StepIntervalSeconds 30
.\platform-minikube.ps1 canary -Action promote
```

### 4. Cloud DevOps & SRE
```powershell
# 1. Audit cloud credentials and host tools
.\platform-multicloud.ps1 doctor -Provider aws
.\platform-multicloud.ps1 doctor -Provider azure

# 2. Plan and apply AWS staging EKS infrastructure
.\platform-multicloud.ps1 plan -Provider aws -Environment staging -Flavor eks
.\platform-multicloud.ps1 apply -Provider aws -Environment staging

# 3. Trigger ArgoCD sync and run post-deploy verification
.\platform-multicloud.ps1 sync-argocd -Provider aws -Environment staging
.\platform-multicloud.ps1 post-deploy -Provider aws -Environment staging -TargetUrl "https://staging.domain.com"
```
