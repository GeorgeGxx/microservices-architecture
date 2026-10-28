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

The platform provides a dual-layer interface for HashiCorp Vault management: scripted orchestration via `platform-minikube.ps1` and direct interactive operations using the local Windows `vault.exe` CLI.

### 1. Scripted Vault Automation (`platform-minikube.ps1`)

| Command | Action | Description |
| :--- | :--- | :--- |
| `.\platform-minikube.ps1 vault -VaultAction status` | Status Check | Inspects seal status, engine health, and cluster endpoint. |
| `.\platform-minikube.ps1 vault -VaultAction init` | Cluster Bootstrap | Enables KV-v2 engine, mounts Transit engine, and provisions encryption keys. |
| `.\platform-minikube.ps1 vault -VaultAction seed` | Dynamic & Static Seeding | Configures PostgreSQL connections, creates dynamic DB roles (`products-db-role`, `orders-db-role`, `inventory-db-role`), and seeds KV-v2 service secrets. |
| `.\platform-minikube.ps1 vault -VaultAction rotate` | Key Rotation | Rotates Transit KMS data-key versions without downtime. |
| `.\platform-minikube.ps1 secrets` | High-Level Wrapper | Shorthand for full Vault initialization, policy creation, and secret synchronization. |

### 2. Local Windows CLI (`vault.exe`) Workflow

When debugging or generating ephemeral tokens locally on Windows:

```powershell
# Mandatory: Set session environment variables (avoids HTTPS default error)
$env:VAULT_ADDR = "http://127.0.0.1:8200"
$env:VAULT_TOKEN = "root"

# Verify connectivity
vault status

# Generate dynamic database credentials (1h TTL)
vault read database/creds/products-db-role
vault read database/creds/orders-db-role
vault read database/creds/inventory-db-role

# List and audit active database leases
vault list sys/leases/lookup/database/creds/products-db-role

# Revoke dynamic leases
vault lease revoke <lease_id>
vault lease revoke -prefix database/creds/
```

---

---

## 📖 Related Operational Guides

For detailed architectural runbooks, security benchmarks, and deep-dive documentation, see:
- [Local Deployment Runbook](./LOCAL_DEPLOYMENT.md)
- [HashiCorp Vault Dynamic Secrets & Rotation Playbook](../01-architecture/ARCHITECTURE.md#-strategic-verification-playbook-dynamic-database-secrets--rotation)
- [Helm Umbrella & Canary Progressive Delivery](./HELM_AND_CANARY.md)
- [Cloudflare Anycast Tunnels](./CLOUDFLARE_TUNNELS.md)
- [DevSecOps Pipelines & Verification](../03-devsecops-and-testing/DEVSECOPS_PIPELINES.md)
- [Dynamic & Chaos Testing](../03-devsecops-and-testing/DYNAMIC_AND_CHAOS_TESTING.md)
