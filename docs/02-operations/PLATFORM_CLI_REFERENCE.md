# Platform CLI Reference

> [!TIP]
> [Enterprise Platform Hub](../../README.md) > **02. Operations** > [Platform CLI Reference](./PLATFORM_CLI_REFERENCE.md)

> [!IMPORTANT]
> **Embedded CLI Documentation:** To eliminate documentation drift and redundancy, all detailed command definitions, options, and operational flags are maintained directly inside the self-documenting PowerShell orchestrators.
> - For local cluster commands: run `.\platform-minikube.ps1 help`
> - For multi-cloud enterprise commands: run `.\platform-multicloud.ps1 help`

All platform PowerShell scripts (`*.ps1`) are standardized on **PowerShell 7+ (`pwsh`)** with `#Requires -Version 7.0` and cross-platform shebangs `#!/usr/bin/env pwsh`. Legacy Windows PowerShell 5.1 (`powershell.exe`) is blocked by `#Requires` to ensure deterministic UTF-8 encoding, modern parameter splatting, and cross-platform parity between Windows, macOS, Linux, and CI/CD runners.

---

## 🏛️ Architecture & Entrypoint Separation

The platform provides two independent, non-cascading PowerShell entrypoints designed for distinct operational scopes:

| Entrypoint | Target Infrastructure | Primary Scope | Cloud & Container Runtime | CI/CD & Delivery Engine | Interactive Help |
| :--- | :--- | :--- | :--- | :--- | :--- |
| [`platform-minikube.ps1`](../../platform-minikube.ps1) | `dev` (Local) | Zero-cloud-cost local development, fast reload, MLOps, Vault, Canary, and full DevSecOps shift-left gates | Minikube (containerd) | GitHub Actions CI + ArgoCD GitOps | `.\platform-minikube.ps1 help` |
| [`platform-multicloud.ps1`](../../platform-multicloud.ps1) | `dev`, `staging`, `prod` | Multi-cloud Terraform lifecycle, Gatekeeper governance, atomic rollback, and endpoint verification across AWS, Azure, and GCP | AWS EKS, Azure AKS, GCP GKE | AWS ArgoCD, Azure DevOps, Bitbucket Pipelines | `.\platform-multicloud.ps1 help` |

---

## 🚀 Execution Model

Each entrypoint is standalone and contains only the runtime helpers required for its platform:

```powershell
# 1. Local Minikube Platform (Single Pane of Glass for Local Development)
.\platform-minikube.ps1 help                     # Displays complete command table & options
.\platform-minikube.ps1 <command> [options]

# 2. Multi-Cloud Platform (AWS EKS/ECS, Azure AKS, GCP GKE)
.\platform-multicloud.ps1 help                    # Displays complete command table & options
.\platform-multicloud.ps1 <command> -Provider <aws|azure|gcp> -Environment <dev|staging|prod> [options]
```

---

## 🛠️ Local Minikube Unified Orchestrator Commands (`platform-minikube.ps1`)

`platform-minikube.ps1` serves as the sole canonical orchestrator for local development, tests, resilience engineering, observability, MLOps, and architecture tooling. All standalone Python utilities are fully wrapped into native CLI subcommands:

### 1. Cluster Lifecycle & Environment Management
| Command | Options | Description |
| :--- | :--- | :--- |
| `up` | `-Fast`, `-WithoutIstio`, `-Build`, `-SkipScans` | Bootstraps full local cluster (Minikube, Istio, Gatekeeper, Vault, Keycloak, Apps, Tunnels). |
| `start` / `resume` | `-Fast` | Fast-resumes Minikube (<30s) bypassing Terraform, Gatekeeper, and Helm re-compilation. |
| `down` / `stop` | `-Destroy` | Safe pause of cluster (preserves DB state and volumes) or full purge with `-Destroy`. |
| `destroy` | | Purges Minikube VM, background tunnels, volume data, and cached modules. |

### 2. Simulation, Traffic & Chaos Engineering (Consolidated Python Engine)
| Command | Key Parameters | Underlying Engine & Description |
| :--- | :--- | :--- |
| `simulate` | `-Scenario <traffic\|ddos\|chaos\|all>`, `-Orders <n>` | Executes realistic shopping sessions, cart events, and Keycloak-authenticated checkout. |
| `ddos` | `-Duration <sec>`, `-Workers <n>` | Sends concurrent GraphQL flood against frontend Nginx rate-limiting edge (20 req/s threshold) to verify HTTP 429 backoff and edge defense. |
| `chaos` | `-ChaosRuns <n>` | Executes runtime chaos tests (concurrent checkout load, out-of-stock SKUs, circuit breaker tripping, idempotency conflict handling). |
| `chaos-drills` | `-TargetService <orders\|products\|...>` | Runs automated Level 5 Hyper-Scale Chaos Drills (Poison Pill injection, Network Latency, Cell Evacuation, Concurrent Duplicate Flooding). |
| `journey` / `e2e` | | Executes full cross-service e-commerce and MLOps end-to-end user journey test suite. |

### 3. Observability, Telemetry & Diagnostics
| Command | Key Parameters | Underlying Engine & Description |
| :--- | :--- | :--- |
| `dashboards` | `-Push` | Curates and generates Grafana Business & Technical JSON dashboards; pushes live to Grafana when `-Push` is supplied. |
| `funnel-demo` | `-Count <n>`, `-Category <name>` | Emits demo `CART_ADD` telemetry events directly to test conversion funnels and abandonment panels. |
| `diagnose` | `-Action <components\|telemetry\|orders-readonly\|all>` | Deep verification of OpenAPI/Swagger specs, Prometheus series, Grafana dashboards, and Keycloak auth. |
| `doctor` | | Comprehensive cluster diagnostic: pods, endpoints, metrics pipeline, and health gates. |
| `urls` | | Displays all active local port-forward URLs, ingress endpoints, and default credentials. |
| `tunnels` | | Manages and supervises background port-forward tunnels for local services. |

### 4. Build, Testing, Security & Quality Gates
| Command | Key Parameters | Underlying Engine & Description |
| :--- | :--- | :--- |
| `build` | `-Service <name>`, `-IncludeMlops`, `-Push`, `-ImageTag <tag>` | Compiles Docker container images for microservices or MLOps stack. |
| `set-tag` | `-ImageTag <tag>`, `-Service <name>`, `-TargetEnv <env>` | Synchronizes image tags across Helm values files via `yq`. |
| `test` | | Executes Java 21 + Maven multi-module reactor unit tests on host. |
| `security-scan` | | Runs 5 shift-left security gates (Gitleaks, TFLint, Trivy, Conftest, Cosign). |
| `smoke` | | Runs router and presentation frontend health & HTTP smoke checks. |
| `contract` | | Executes Newman/Postman API contract integration suite (23/23 tests, 54 assertions). |
| `performance` | | Runs Grafana k6 SLA latency, throughput, and performance benchmarks. |
| `dast` | | Executes OWASP ZAP baseline dynamic application security scan against frontend. |

### 5. MLOps, FinOps & Architecture Tooling
| Command | Key Parameters | Underlying Engine & Description |
| :--- | :--- | :--- |
| `mlops` | | Deploys MLflow tracking, Kafka-to-Parquet capture, and baseline demand model training. |
| `mlops-train` | `-Days <n>` | Runs demand forecasting model training via `mlops/training.ps1`. |
| `mlops-data` | `-Days <n>` | Generates synthetic historical sales dataset via `mlops/generate_sample_sales.py`. |
| `postman-gen` | | Generates the unified Newman/Postman 23-request collection JSON (`microservices.postman_collection.json`). |
| `diagrams` | | Generates and synchronizes 17 architecture blueprint tabs in `docs/Diagrams.drawio`. |
| `finops` | `-Environment <dev\|staging\|prod>` | Offline illustrative FinOps cost model estimate and rightsizing analysis. |
| `cost` | | Queries live Kubernetes workload costs via `kubectl-cost` and OpenCost. |
| `canary` | `-Action <weight\|rollout\|promote\|retire>` | Controls progressive canary rollout and traffic splits on products-service. |
| `cloudflare` | `-Action <start\|status\|stop>` | Manages Cloudflare Anycast Quick Tunnels for external demo access. |
| `compose-router` | | Composes Cosmo Router GraphQL Federation v2 execution config. |
| `graph` | | Generates visual Terraform dependency graph via Graphviz dot. |
| `tools` | `-Install` | Audits host CLI dependencies (pass `-Install` to attempt WinGet installation). |

---

## 🛡️ Operational Safeguards & State Management

### 1. Terraform State Serialization
- Terraform commands are serialized per working directory. Terraform `init` uses `-upgrade` and retries transient Windows provider-file locks.
- Cloud operations require configured durable remote backends (AWS S3 + DynamoDB lock, Azure Blob Storage lease, GCP Cloud Storage).
- Minikube's `down -Destroy` cleans up local Terraform working directories and cluster resources while preserving downloaded provider binaries under `.terraform/providers`.

### 2. Multi-Cloud Production Boundaries
- Production environments provision dual data-plane clusters (`primary` and `secondary`).
- Commands accept `-DataPlane all|primary|secondary` to scope operations without mutating shared remote state.
- Destruction (`destroy`) requires interactive confirmation unless `-AutoApprove` is explicitly supplied.

### 3. Application Delivery & Workload Hand-Off
The CLI provisions infrastructure and validates deployment readiness, handing off application release delivery to the designated CI/CD engines:
- **AWS EKS:** GitHub Actions CI produces signed images; Argo CD executes GitOps continuous reconciliation (`sync-argocd`).
- **Azure AKS:** Azure DevOps pipelines deploy releases via the shared Helm umbrella chart; pipeline stages own atomic rollback (`apply-workloads`, `rollback`).
- **GCP GKE:** Bitbucket Pipelines deploys container releases to GKE via Helm and manages deployment rollbacks (`apply-workloads`, `rollback`).

---

## 🔐 HashiCorp Vault Management & CLI Integration

The platform provides scripted Vault orchestration via `platform-minikube.ps1`:

| Command | Action | Description |
| :--- | :--- | :--- |
| `.\platform-minikube.ps1 vault -VaultAction status` | Status Check | Inspects seal status, engine health, and cluster endpoint. |
| `.\platform-minikube.ps1 vault -VaultAction seed` | Dynamic & Static Seeding | Runs [`scripts/vault-init.sh`](../../scripts/vault-init.sh) to configure KV-v2, Transit KMS, and all 6 PostgreSQL 18 dynamic DB roles (`products`, `orders`, `inventory`, `payments`, `fulfillment`, `analytics`). |
| `.\platform-minikube.ps1 vault -VaultAction k8s-auth` | Kubernetes Auth & Policies | Binds isolated Vault policies and Kubernetes auth roles for all 7 microservices. |
| `.\platform-minikube.ps1 vault -VaultAction istio-pki` | Istio Mesh PKI CA | Provisions or rotates the Vault Intermediate CA signing `istio-system/cacerts`. |
| `.\platform-minikube.ps1 secrets` | High-Level Wrapper | Generates CSPRNG secrets and synchronizes Kubernetes Secrets and Vault KV-v2. |

> For interactive `vault.exe` Windows CLI commands (`$env:VAULT_ADDR`, minting dynamic PostgreSQL credentials, and auditing/revoking leases), see [Local Deployment Runbook — Useful Commands](./LOCAL_DEPLOYMENT.md#useful-commands).

---

## 📖 Related Operational Guides

For detailed architectural runbooks, security benchmarks, and deep-dive documentation, see:
- [Local Deployment Runbook](./LOCAL_DEPLOYMENT.md)
- [HashiCorp Vault Dynamic Secrets & Rotation Architecture](../01-architecture/ARCHITECTURE.md#-dynamic-database-secrets-engine--rotation-architecture)
- [Helm Umbrella & Canary Progressive Delivery](./HELM_AND_CANARY.md)
- [Cloudflare Anycast Tunnels](./CLOUDFLARE_TUNNELS.md)
- [DevSecOps Pipelines & Verification](../03-devsecops-and-testing/DEVSECOPS_PIPELINES.md)
- [Dynamic & Chaos Testing](../03-devsecops-and-testing/DYNAMIC_AND_CHAOS_TESTING.md)
