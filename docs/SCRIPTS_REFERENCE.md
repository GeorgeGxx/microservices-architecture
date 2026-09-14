# 🛠️ Enterprise Automation Scripts & CLI Reference Manual

> Exhaustive reference manual for the unified platform CLI (platform.ps1), multi-cloud lifecycle scripts (AWS, Azure, GCP), FinOps snapshot cleanup, and platform operational tooling.

---

## 🚀 Enterprise Platform Unified CLI (`platform.ps1`)

The repository includes a single, master PowerShell orchestrator [`platform.ps1`](./platform.ps1) providing a standardized entrypoint for all platform operations across **4 target platforms** (`minikube`, `aws`, `azure`, `gcp`) and **3 environments** (`dev`, `staging`, `prod`):

```powershell
.\platform.ps1 <command> [-Platform minikube|aws|azure|gcp] [-Environment dev|staging|prod] [options]
```

### 📋 Complete Combinations Reference Guide

#### 1. 🚀 Bootstrap & Deployment (`up` / `bootstrap`)

| Platform | Command / Combination | Description & Effects |
| :--- | :--- | :--- |
| **Minikube** | `.\platform.ps1 up` | Default bootstrap: Minikube cluster, Istio Demo profile, Envoy sidecars, Gatekeeper OPA, Keycloak + `db-keycloak`, Vault, Data tier, Apps, Grafana/Prometheus, Tunnels & FinOps. |
| **Minikube** | `.\platform.ps1 up -Platform minikube -WithIstio` | Explicitly enables Istio service mesh, STRICT mTLS and Envoy proxy injection. |
| **Minikube** | `.\platform.ps1 up -Platform minikube -WithoutIstio` | Native Kubernetes mode without Envoy sidecars or Istio control plane overhead (saves 1.5 GB RAM). |
| **Minikube** | `.\platform.ps1 up -DeployCanary` | Provisions base microservices plus version `v2` in Canary mode with 90/10 Istio traffic routing. |
| **Minikube** | `.\platform.ps1 up -SkipScans` | Fast-track bootstrap: skips pre-flight Gitleaks, TFLint, Trivy, and Cosign validations. |
| **Minikube** | `.\platform.ps1 up -Cpus 8 -MemoryMb 8192 -DiskSize 50g` | Custom hardware allocation for lower-spec developer workstations. |
| **AWS** | `.\platform.ps1 up -Platform aws -Environment dev` | Deploys AWS Dev tier (corresponds to `develop` branch, namespace `dev`, burstable resources). |
| **AWS** | `.\platform.ps1 up -Platform aws -Environment staging` | Deploys AWS Staging tier (`staging` branch, namespace `staging`, medium performance: 2 replicas, 250m-500m CPU). |
| **AWS** | `.\platform.ps1 up -Platform aws -Environment prod` | Deploys AWS Production tier (`main`/`master` branch, namespace `production`, high performance HA: 3-10 replicas, ALB, Canary). |
| **AWS** | `.\platform.ps1 up -Platform aws -Environment <env> -AutoApprove` | Automated, non-interactive Terraform apply for CI/CD runners. |
| **Azure** | `.\platform.ps1 up -Platform azure -Environment dev` | Deploys Azure Dev tier (corresponds to `develop` branch, namespace `dev`, burstable B-series). |
| **Azure** | `.\platform.ps1 up -Platform azure -Environment staging` | Deploys Azure Staging tier (`staging` branch, namespace `staging`, medium performance D-series). |
| **Azure** | `.\platform.ps1 up -Platform azure -Environment prod` | Deploys Azure Production tier (`main`/`master` branch, namespace `production`, high performance HA, App Gateway). |
| **Azure** | `.\platform.ps1 up -Platform azure -Environment <env> -AutoApprove` | Automated non-interactive Terraform apply for Azure DevOps pipelines. |
| **GCP** | `.\platform.ps1 up -Platform gcp -Environment dev` | Deploys GCP Dev tier (corresponds to `develop` branch, namespace `dev`, e2-standard). |
| **GCP** | `.\platform.ps1 up -Platform gcp -Environment staging` | Deploys GCP Staging tier (`staging` branch, namespace `staging`, medium performance). |
| **GCP** | `.\platform.ps1 up -Platform gcp -Environment prod` | Deploys GCP Production tier (`main`/`master` branch, namespace `production`, high performance HA, Cloud Armor). |
| **GCP** | `.\platform.ps1 up -Platform gcp -Environment <env> -AutoApprove` | Automated non-interactive Terraform apply for Bitbucket Pipelines. |

---

#### 2. ⏸️ Teardown, Pause & Cluster Purge (`down` / `stop` / `destroy`)

| Command / Combination | Platform | Description & Effects |
| :--- | :--- | :--- |
| `.\platform.ps1 down` | Minikube | Gracefully terminates background tunnels and pauses Minikube. Preserves all container images, database data, and state. |
| `.\platform.ps1 down -Destroy` | Minikube | Deletes the Minikube VM/container, purges persistent volumes, and cleans local Terraform state. |
| `.\platform.ps1 destroy -Platform minikube` | Minikube | Direct alias for complete Minikube cluster and state purge. |
| `.\platform.ps1 down -Platform aws -Environment <dev\|staging\|prod>` | AWS | Runs `terraform destroy` against the specified AWS workspace. |
| `.\platform.ps1 destroy -Platform aws -Environment prod -AutoApprove` | AWS | Non-interactive purge of AWS production resources. |
| `.\platform.ps1 down -Platform azure -Environment <dev\|staging\|prod>` | Azure | Runs `terraform destroy` against the specified Azure workspace. |
| `.\platform.ps1 destroy -Platform azure -Environment prod -AutoApprove` | Azure | Non-interactive purge of Azure production resources. |
| `.\platform.ps1 down -Platform gcp -Environment <dev\|staging\|prod>` | GCP | Runs `terraform destroy` against the specified GCP workspace. |
| `.\platform.ps1 destroy -Platform gcp -Environment prod -AutoApprove` | GCP | Non-interactive purge of GCP production resources. |

---

#### 3. 📝 Terraform Infrastructure Planning & Apply (`plan` / `apply`)

| Command / Combination | Platform | Description & Effects |
| :--- | :--- | :--- |
| `.\platform.ps1 plan -Platform minikube` | Minikube | Generates the Graphviz visual dependency diagram (`docs/terraform-graph.png`). |
| `.\platform.ps1 plan -Platform aws -Environment <dev\|staging\|prod>` | AWS | Executes `terraform plan` for the selected AWS workspace and outputs plan file. |
| `.\platform.ps1 plan -Platform azure -Environment <dev\|staging\|prod>` | Azure | Executes `terraform plan` for the selected Azure workspace. |
| `.\platform.ps1 plan -Platform gcp -Environment <dev\|staging\|prod>` | GCP | Executes `terraform plan` for the selected GCP workspace. |
| `.\platform.ps1 apply -Platform aws -Environment staging -AutoApprove` | AWS | Provisions AWS staging infrastructure without interactive prompts. |
| `.\platform.ps1 apply -Platform azure -Environment prod -AutoApprove` | Azure | Provisions Azure production infrastructure without interactive prompts. |
| `.\platform.ps1 apply -Platform gcp -Environment dev -AutoApprove` | GCP | Provisions GCP dev infrastructure without interactive prompts. |

---

#### 4. 🔄 Automated Emergency Rollbacks (`rollback`)

| Command / Combination | Target | Recovery Action Performed |
| :--- | :--- | :--- |
| `.\platform.ps1 rollback` | Minikube | Rolls back the Helm umbrella release in namespace `dev` to the previous stable revision. |
| `.\platform.ps1 rollback -Platform aws -Environment staging` | AWS | Initiates emergency rollback: releases S3/DynamoDB state lock and triggers ArgoCD sync fallback. |
| `.\platform.ps1 rollback -Platform aws -Environment prod -LockId <ID>` | AWS | Forces release of a specific DynamoDB state lock (`terraform force-unlock <ID>`) and triggers rollback. |
| `.\platform.ps1 rollback -Platform azure -Environment staging` | Azure | Releases Azure Blob Storage state lease and triggers Helm rollback on AKS. |
| `.\platform.ps1 rollback -Platform azure -Environment prod -LockId <ID>` | Azure | Unlocks Azure Blob storage lease and executes production fallback. |
| `.\platform.ps1 rollback -Platform gcp -Environment staging` | GCP | Releases GCS state lock and executes GKE deployment rollback to previous replica revision. |
| `.\platform.ps1 rollback -Platform gcp -Environment prod -LockId <ID>` | GCP | Clears GCS state lock and triggers production rollback. |

---

#### 5. 🔍 Health Diagnostics & Verification (`doctor` / `verify` / `status`)

| Command / Combination | Target | Diagnostic Scope |
| :--- | :--- | :--- |
| `.\platform.ps1 doctor` | Minikube | Verifies pods across `dev`, `observability`, `auth`, `vault`, `data`, `argocd`, `gatekeeper-system`, active NodePorts, and runs synthetic OPA admission test. |
| `.\platform.ps1 doctor -Platform aws -Environment staging` | AWS | Inspects AWS EKS pod status, ALB ingress controller, and IRSA bindings. |
| `.\platform.ps1 doctor -Platform azure -Environment prod` | Azure | Inspects Azure AKS pod status, Application Gateway ingress, and Workload Identity. |
| `.\platform.ps1 doctor -Platform gcp -Environment dev` | GCP | Inspects Google GKE pod status, Cloud Armor LB, and Workload Identity. |

---

#### 6. 💰 FinOps Cloud Cost Breakdown & Savings (`cost` / `finops`)

| Command / Combination | Environment | Analysis Performed |
| :--- | :--- | :--- |
| `.\platform.ps1 cost` | Minikube | Air-gapped offline cost analysis: computes local developer cost ($0/mo) and calculates monthly savings vs. AWS ($1,864/mo), Azure ($1,792/mo), and GCP ($1,680/mo). |
| `.\platform.ps1 cost -Environment staging` | Staging | Displays medium performance tier monthly spending breakdown across compute, databases, cache, and networking. |
| `.\platform.ps1 cost -Environment prod` | Production | Displays high performance HA tier monthly cost breakdown across multi-AZ clusters, managed databases, and enterprise services. |

---

#### 7. 🛠️ Host CLI Audit & Automated Winget Installation (`tools`)

| Command / Combination | Mode | Description |
| :--- | :--- | :--- |
| `.\platform.ps1 tools` | Audit Only | Fast audit (< 1s) checking presence and version of 17 essential platform tools. Excludes 9 non-essential CLIs. |
| `.\platform.ps1 tools -Install` | Unattended Install | Automatically installs any missing tools via `winget install --id ... --silent --accept-package-agreements`. |

---

#### 8. ⚡ Productivity, Security & Verification Utilities

| Command | Action Performed |
| :--- | :--- |
| `.\platform.ps1 urls` | Prints interactive colorized dashboard of all active frontend, API Gateway, Keycloak IAM, Vault UI, Kiali, ArgoCD, Grafana, and Prometheus URLs with credentials. |
| `.\platform.ps1 smoke` | Executes automated synthetic integration smoke tests against API Gateway and microservices validating health, latency, and negative security gates. |
| `.\platform.ps1 tunnels` | Launches the resilient background port-forward supervisor daemon with automatic reconnection. |
| `.\platform.ps1 secrets [-Environment <dev\|staging\|prod>]` | Generates high-entropy CSPRNG cryptographic secrets (JWT keys, DB passwords, Keycloak client secrets) for Kubernetes manifests or `.env`. |
| `.\platform.ps1 security-scan` | Runs local pre-flight security suite: Gitleaks (secret detection), TFLint (Terraform static analysis), Trivy (chart/image vulnerabilities), and Cosign (signing validation). |
| `.\platform.ps1 graph` | Generates a visual Terraform dependency graph PNG at `docs/terraform-graph.png` using Graphviz (`dot`). |
| `.\platform.ps1 diagrams` | Synchronizes and programmatically regenerates all 12 architectural tabs in [`docs/Diagrams.drawio`](./Diagrams.drawio) via Python. |

---

## 🛠️ Enterprise Cloud Automation & FinOps Tooling (`scripts/cloud/`)

The platform consolidates production-grade CLI tools for multi-cloud governance, disaster recovery, security auditing, and storage lifecycle management across AWS, Azure, and GCP:

| Tool | Cloud | Purpose | Runbook Command |
| :--- | :---: | :--- | :--- |
| **[`manage-aws.ps1`](../scripts/cloud/aws/manage-aws.ps1)** | ☁️ AWS | **AWS Operations Orchestrator:** Manages ECR login, EKS credentials, Helm deployments, and cluster status. | `pwsh scripts/cloud/aws/manage-aws.ps1 -Action deploy -Environment prod` |
| **[`audit-aws.py`](../scripts/cloud/aws/audit-aws.py)** | ☁️ AWS | **Enterprise Security & FinOps Auditor:** Unified audit engine consolidating IAM key age, security groups, orphan EBS/EIPs, ACM certs, CloudWatch retention, RDS snapshots, S3 policies, and resource inventory. | `python scripts/cloud/aws/audit-aws.py --module all` |
| **[`manage-azure.ps1`](../scripts/cloud/azure/manage-azure.ps1)** | ☁️ Azure | **Azure Operations Orchestrator:** Manages ACR login, AKS credentials, Helm deployments, and cluster diagnostics. | `pwsh scripts/cloud/azure/manage-azure.ps1 -Action deploy -Environment staging` |
| **[`manage-gcp.ps1`](../scripts/cloud/gcp/manage-gcp.ps1)** | ☁️ GCP | **GCP Operations & FinOps Orchestrator:** Handles GAR authentication, GKE deployment, and automated Persistent Disk snapshot purging. | `pwsh scripts/cloud/gcp/manage-gcp.ps1 -Action disk-cleanup -Environment prod -RetentionDays 14` |
| **[`start-cloudflare-tunnels.ps1`](../scripts/cloud/cloudflare/start-cloudflare-tunnels.ps1)** | 🌐 Cloudflare | **Zero-Trust Ingress:** Launches Cloudflare Zero-Trust tunnels to securely expose services without opening public inbound ports. | `pwsh scripts/cloud/cloudflare/start-cloudflare-tunnels.ps1` |
| **[`local-cost-estimator.py`](../scripts/cloud/terraform/local-cost-estimator.py)** | ☁️ Multi-Cloud | **FinOps Cost Estimator:** Analyzes Terraform plan outputs to predict monthly cloud spending across AWS, Azure, and GCP resources. | `python scripts/cloud/terraform/local-cost-estimator.py --dir terraform/environments/aws` |
| **[`terraform-apply.ps1`](../scripts/cloud/terraform/terraform-apply.ps1)** | ☁️ Multi-Cloud | **IaC Deployment:** Automated execution of Terraform apply with workspace selection, state locking, and auto-approval gates. | `pwsh scripts/cloud/terraform/terraform-apply.ps1 -Platform aws -Environment dev` |
| **[`terraform-plan.ps1`](../scripts/cloud/terraform/terraform-plan.ps1)** | ☁️ Multi-Cloud | **IaC Plan & Spec:** Generates and validates speculative execution plans against remote cloud backends. | `pwsh scripts/cloud/terraform/terraform-plan.ps1 -Platform azure -Environment staging` |
| **[`terraform-bootstrap-backend.ps1`](../scripts/cloud/terraform/terraform-bootstrap-backend.ps1)** | ☁️ Multi-Cloud | **State Backend Bootstrapper:** Pre-provisions S3/DynamoDB, Azure Blob Storage, or GCS buckets for remote state management. | `pwsh scripts/cloud/terraform/terraform-bootstrap-backend.ps1 -Platform gcp` |

#### Detailed Cloud Automation Playbooks:

##### 1. 🔍 Unified AWS Security, Governance & FinOps Auditor (`audit-aws.py`)
The **[`audit-aws.py`](../scripts/cloud/aws/audit-aws.py)** tool consolidates 9 critical Well-Architected governance functions into a single command-line interface:
* **IAM Credential Age & MFA:** Checks access keys older than 90 days and flags inactive credentials.
* **Security Group Overly Permissive Ingress:** Flags `0.0.0.0/0` open rules on sensitive ports (SSH 22, DBs 5432/3306, KubeAPI 6443).
* **FinOps Orphan Cleaner:** Detects unattached EBS volumes and unassociated Elastic IPs.
* **ACM Certificate Expiration:** Proactively monitors SSL/TLS certificate validity on ALBs and CloudFront.
* **CloudWatch Retention Enforcer:** Audits infinite retention log groups and applies compliant limits (14/30/90 days).
* **RDS PostgreSQL Snapshots:** Triggers automated pre-deployment snapshots with retention management.
* **S3 Security Policies:** Verifies TLS 1.2+ HTTPS enforcement and CloudFront Origin Access Control (OAC).
* **Resource Inventory Sweep:** Discovers all active EKS, RDS, ECR, ALB, and VPC instances.

```bash
# Run a complete security, compliance, and FinOps sweep:
python scripts/cloud/aws/audit-aws.py --module all

# Audit IAM credentials for CIS compliance:
python scripts/cloud/aws/audit-aws.py --module iam

# Inspect security groups for dangerous 0.0.0.0/0 ingress:
python scripts/cloud/aws/audit-aws.py --module security-groups

# Detect orphaned EBS volumes and Elastic IPs:
python scripts/cloud/aws/audit-aws.py --module orphans --dry-run

# Audit CloudWatch log retention policies:
python scripts/cloud/aws/audit-aws.py --module cloudwatch --retention-days 30
```

##### 2. 🧹 GCP Persistent Disk & Snapshot FinOps Purger (`manage-gcp.ps1`)
Integrated directly into **[`manage-gcp.ps1`](../scripts/cloud/gcp/manage-gcp.ps1)**:
* Purges expired Persistent Disk snapshots generated by GKE stateful sets (Kafka, PostgreSQL) older than $N$ days.
* Includes dry-run simulation mode to audit reclaimable disk storage without deleting data.

```powershell
# Safe preview mode (audit disk snapshots older than 14 days):
pwsh scripts/cloud/gcp/manage-gcp.ps1 -Action disk-cleanup -Environment prod -RetentionDays 14 -DryRun

# Execute live purge of orphaned snapshots:
pwsh scripts/cloud/gcp/manage-gcp.ps1 -Action disk-cleanup -Environment prod -RetentionDays 30
```

---

## 🛡️ Cloud-Agnostic DevSecOps CLI Tooling (`scripts/devsecops/`)

The platform provides lightweight, cloud-agnostic tools for post-deployment verification, zero-trust credential bootstrapping, automated cluster provisioning and lifecycle management:

| Tool | Purpose | Key DevSecOps Gates | Runbook Command |
| :--- | :--- | :--- | :--- |
| **[`platform-minikube.ps1`](./platform-minikube.ps1)** | **Dedicated Minikube Orchestrator (`dev` / `develop`):** Configures Minikube, Istio, Gatekeeper OPA, Vault, Keycloak + `db-keycloak`, Prometheus, Grafana, Microservices, FinOps, and Tunnels. | • Minikube sizing (12 CPUs, 12 GB RAM)<br/>• Istio mesh injection with `-WithIstio` / `-WithoutIstio`<br/>• Shift-left security scans & Graphviz | `.\platform-minikube.ps1 up` |
| **[`verify-platform.ps1`](../scripts/devsecops/verify-platform.ps1)** | **Deep Diagnostic Health Audit:** Validates pods, active NodePorts, Prometheus targets, and Gatekeeper admission policies. | • Pod Readiness check in all namespaces<br/>• OPA Constraint validation<br/>• Health reporting table | `.\scripts\devsecops\verify-platform.ps1` |
| **[`install-cli-tools.ps1`](../scripts/devsecops/install-cli-tools.ps1)** | **Winget CLI Auditor & Installer:** Audits and silently installs 18 platform CLI tools for IaC, Security, Kubernetes and Productivity. | • Automated PATH detection<br/>• Idempotent non-interactive Winget installation<br/>• Formatted status & version table | `.\scripts\devsecops\install-cli-tools.ps1 -Install` |
| **[`endpoint-smoke-test.py`](../scripts/devsecops/endpoint-smoke-test.py)** | **Synthetic Post-Deployment Smoke Prober:** Works identically across Minikube, EKS, AKS, and GKE. | • Actuator Health (`/actuator/health`)<br/>• Prometheus Metrics (`/actuator/prometheus`)<br/>• Public Catalog API (`/api/product`)<br/>• **Negative Security Auth Gate:** Asserts 401/403 on unauthenticated routes (`/api/order`)<br/>• Latency SLO validation (< 500 ms) | `python scripts/devsecops/endpoint-smoke-test.py --base-url http://localhost:8080 --max-latency-ms 500` |
| **[`generate-secure-secrets.py`](../scripts/devsecops/generate-secure-secrets.py)** | **Zero-Trust Credential & Secret Generator:** Replaces default passwords with high-entropy cryptographic keys (CSPRNG). | • Generates database passwords, Keycloak client secrets, and 256-bit JWT keys<br/>• Exports directly to `.env`, JSON, or Kubernetes `Secret` YAML manifests | `python scripts/devsecops/generate-secure-secrets.py --format k8s-yaml --namespace staging` |
| **[`supervise-tunnels.py`](../scripts/devsecops/supervise-tunnels.py)** | **Resilient Port-Forward Tunnel Supervisor:** Maintains background port-forwarding daemons with automatic reconnects. | • Supervises frontend (4200), gateway (8080), keycloak (8181), vault (8200), grafana (3000), argo (8088)<br/>• Recovers from connection drops | `python scripts/devsecops/supervise-tunnels.py` |
| **[`teardown-local-devsecops.ps1`](../scripts/devsecops/teardown-local-devsecops.ps1)** | **Platform Teardown & Resource Release:** Pauses Minikube or completely purges cluster, state and tunnels. | • Graceful pod drain<br/>• Reclaims 12 CPUs and 12 GB RAM<br/>• Optional `-DeleteCluster` cleans 80 GB disk | `.\scripts\devsecops\teardown-local-devsecops.ps1 -DeleteCluster` |

---

## 📂 Comprehensive Scripts Portfolio Directory (`scripts/`)

Below is the complete inventory of all platform automation scripts and their operational responsibilities:

### 1. `scripts/devsecops/` (Cluster Lifecycle, Security & Verification)
- **`verify-platform.ps1`**: Deep health diagnostic verifying pod statuses, nodeports, Prometheus metrics endpoints, and active Gatekeeper OPA constraints.
- **`install-cli-tools.ps1`**: Audits installed platform CLI tools and automates non-interactive Winget installations.
- **`endpoint-smoke-test.py`**: Integration smoke tester verifying HTTP status, Actuator endpoints, latency SLOs, and negative authorization boundaries.
- **`generate-secure-secrets.py`**: Generates high-entropy cryptographic secrets (CSPRNG) for DB credentials, JWT signing, and Keycloak clients.
- **`supervise-tunnels.py`**: Resilient background port-forward daemon maintaining connections to frontend, gateway, keycloak, vault, and grafana.
- **`teardown-local-devsecops.ps1`**: Gracefully stops local platform processes, pauses Minikube, or executes full cluster deletion.

### 2. `scripts/cloud/terraform/` (Terraform Orchestration & FinOps)
- **`local-cost-estimator.py`**: Air-gapped FinOps engine calculating cloud cost baselines across `minikube` (savings), `staging`, and `prod`.
- **`terraform-bootstrap-backend.ps1`**: Creates S3 state bucket and DynamoDB locking table with SSE-KMS encryption.
- **`terraform-plan.ps1`**: Executes parameterized `terraform plan` generating environment-specific plan output files.
- **`terraform-apply.ps1`**: Applies Terraform infrastructure changes with automatic workspace selection (`dev`, `staging`, `prod`).

### 3. `scripts/cloud/aws/` (Unified AWS Operations & Well-Architected Governance)

- **`manage-aws.ps1`**: Canonical, zero-redundancy Amazon Web Services operations orchestrator consolidating ECR authentication, EKS credentials, and Helm deployments:
  - **Key Features:**
    - **Single Source of Truth:** Replaces legacy `deploy-eks.ps1` and `ecr-login.ps1` with a unified CLI maintaining 100% architectural symmetry with Azure and GCP.
    - **Multi-Environment Resolution:** Automatically targets EKS clusters (`msa-aws-$Environment-eks`), resolves AWS Account ID via STS caller identity, and deploys to namespaces `dev`, `staging`, or `production`.
    - **Amazon ECR Docker Authentication:** Seamlessly fetches authorization token (`aws ecr get-login-password`) and logs in Docker with `$AccountId.dkr.ecr.$AwsRegion.amazonaws.com`.
    - **EKS Kubeconfig Synchronization:** Auto-updates local kubeconfig (`aws eks update-kubeconfig`) ensuring immediate connectivity.
    - **Manifest & Ingress Enforcement:** Automatically validates and applies AWS GP3 `storageclass.yaml` and Traefik Ingress with AWS NLB `ingress.yaml` from `k8s/eks/`.
    - **Umbrella Helm Deployment:** Executes `helm upgrade --install` with environment-specific values (`helm/values/values-eks-$Environment.yaml`).
    - **Audit Delegation:** Directly triggers Well-Architected governance audits via `-Action audit -AuditModule <mod>`.
    - **Cluster Diagnostics:** `-Action status` queries active EKS cluster metadata, Kubernetes version, API server endpoint, and node readiness.
  - **Syntax & Parameters:**
    ```powershell
    .\scripts\cloud\aws\manage-aws.ps1 [-Action all|deploy|login|credentials|audit|status] [-Environment dev|staging|prod] [-AwsRegion <region>] [-AccountId <id>] [-ClusterName <cluster>] [-AuditModule <mod>]
    ```
  - **Examples:**
    ```powershell
    # Full deployment to AWS Staging (ECR login + EKS credentials + Helm deploy):
    .\scripts\cloud\aws\manage-aws.ps1 -Action all -Environment staging

    # Authenticate Docker CLI with Amazon ECR:
    .\scripts\cloud\aws\manage-aws.ps1 -Action login -AwsRegion us-east-1

    # Deploy microservices to EKS Production:
    .\scripts\cloud\aws\manage-aws.ps1 -Action deploy -Environment prod

    # Trigger security & governance audit for IAM and Security Groups:
    .\scripts\cloud\aws\manage-aws.ps1 -Action audit -AuditModule security-groups

    # Display EKS cluster health and node readiness:
    .\scripts\cloud\aws\manage-aws.ps1 -Action status -Environment staging
    ```

- **`audit-aws.py`**: Enterprise AWS Well-Architected Security, Compliance & FinOps Auditor consolidating 9 specialized audit tools into a single engine:
  - **Modules Consolidated:**
    - `iam`: Audits IAM access keys for expiration (>90 days), unused credentials, and MFA compliance (`audit-iam-credentials.py`).
    - `security-groups`: Scans for overly permissive `0.0.0.0/0` ingress rules exposing internal ports (`check-security-groups.py`).
    - `orphans`: FinOps detector for unattached EBS volumes and unassociated Elastic IPs (`clean-orphan-resources.py`).
    - `acm`: SSL/TLS certificate expiration watcher alerting on certificates expiring within 30 days (`acm-cert-expiration-watcher.py`).
    - `cloudwatch`: Enforces strict retention policies (e.g. 30 days) on CloudWatch log groups to curb runaway costs (`enforce-cloudwatch-retention.py`).
    - `rds`: Automates manual snapshot backups for Amazon RDS PostgreSQL instances (`rds-snapshot-backup.py`).
    - `s3`: Enforces TLS 1.2+ bucket policies, CloudFront OAC, and S3 versioning (`s3-bucket-security-policy.py`).
    - `inventory`: Discovers active EKS, ECR, RDS, ALB, and VPC resources (`audit-aws-resources.py`).
    - `all`: Sequentially audits all 8 governance pillars.
  - **Syntax & Parameters:**
    ```powershell
    python scripts/cloud/aws/audit-aws.py [--module all|iam|security-groups|orphans|acm|cloudwatch|s3|rds|inventory] [--region <reg>] [--dry-run] [--retention-days <days>]
    ```
  - **Examples:**
    ```powershell
    # Complete multi-pillar security and governance audit:
    python scripts/cloud/aws/audit-aws.py --module all

    # FinOps: Audit and identify unattached EBS volumes and idle Elastic IPs:
    python scripts/cloud/aws/audit-aws.py --module orphans

    # Security: Detect overly permissive Security Groups open to 0.0.0.0/0:
    python scripts/cloud/aws/audit-aws.py --module security-groups

    # CloudWatch: Enforce 30-day log retention policy (preview with --dry-run):
    python scripts/cloud/aws/audit-aws.py --module cloudwatch --retention-days 30 --dry-run
    ```

### 4. `scripts/cloud/azure/` (Unified Azure Cloud Operations)

- **`manage-azure.ps1`**: Canonical, zero-redundancy Azure operations orchestrator that consolidates ACR authentication, AKS credential synchronization, and Helm deployments across all 3 cloud tiers:
  - **Key Features:**
    - **Single Source of Truth:** Replaces the legacy `acr-login.ps1` and `deploy-aks.ps1` scripts with a unified, parameter-driven workflow.
    - **Multi-Environment Resolution:** Automatically resolves resource groups (`msa-azure-$Environment-rg`), AKS clusters (`msa-azure-$Environment-aks`), ACR registries (`msaacr$Environment`), and destination namespaces (`dev`, `staging`, `production`).
    - **Zero-Touch Kubeconfig Sync:** Runs `az aks get-credentials` with `--overwrite-existing` to guarantee seamless local or CI/CD runner connectivity.
    - **Manifest & Ingress Enforcement:** Automatically validates and applies Azure-specific `storageclass.yaml` and Traefik `ingress.yaml` from `k8s/aks/`.
    - **Umbrella Helm Deployment:** Upgrades/installs the `microservices-umbrella` Helm chart with environment-tailored values (`helm/values/values-aks-$Environment.yaml`).
    - **Resilient Pipeline Fallback:** In `-Action all`, continues deployment smoothly even if direct Docker daemon access is unavailable on air-gapped or restricted runners.
    - **Cluster Diagnostics:** `-Action status` queries provisioning state, agent pool node count, and active Kubernetes nodes.
  - **Syntax & Parameters:**
    ```powershell
    .\scripts\cloud\azure\manage-azure.ps1 [-Action all|deploy|login|credentials|status] [-Environment dev|staging|prod] [-AcrName <name>] [-ResourceGroup <rg>] [-ClusterName <cluster>]
    ```
  - **Examples:**
    ```powershell
    # Full deployment to Azure Staging (ACR login + AKS credentials + Helm deploy):
    .\scripts\cloud\azure\manage-azure.ps1 -Action all -Environment staging

    # Standalone ACR Docker authentication:
    .\scripts\cloud\azure\manage-azure.ps1 -Action login -Environment prod -AcrName "mycustomacr"

    # Deploy microservices to AKS Production:
    .\scripts\cloud\azure\manage-azure.ps1 -Action deploy -Environment prod

    # Inspect AKS cluster health and node readiness:
    .\scripts\cloud\azure\manage-azure.ps1 -Action status -Environment staging
    ```

### 5. `scripts/cloud/gcp/` (Unified Google Cloud Operations)

- **`manage-gcp.ps1`**: Canonical, zero-redundancy Google Cloud Platform orchestrator consolidating Artifact Registry authentication, GKE cluster deployments, and FinOps persistent disk lifecycle management:
  - **Key Features:**
    - **Single Source of Truth:** Replaces legacy `deploy-gke.ps1`, `gar-login.ps1`, and `gke-disk-cleanup.py` with a single, production-grade CLI.
    - **Multi-Environment Resolution:** Automatically resolves GKE clusters (`msa-gcp-$Environment-gke`), GCP projects (`msa-gcp-$Environment`), Artifact Registry endpoints (`$GcpRegion-docker.pkg.dev`), and namespaces (`dev`, `staging`, `production`).
    - **Google Artifact Registry (GAR) Auth:** Configures Docker credential helper integration seamlessly via `gcloud auth configure-docker --quiet`.
    - **Kubeconfig & GKE Credentials:** Connects to GKE Autopilot or Standard clusters via `gcloud container clusters get-credentials`.
    - **Manifest & Ingress Application:** Enforces GCP Persistent Disk `storageclass.yaml` and Google Cloud HTTP(S) Load Balancer `ingress.yaml` from `k8s/gke/`.
    - **Umbrella Helm Deployment:** Executes `helm upgrade --install` with environment-specific values (`helm/values/values-gke-$Environment.yaml`).
    - **FinOps Persistent Disk Snapshot Lifecycle:** Audits and purges expired Persistent Disk snapshots generated by Kafka, PostgreSQL, and Redis workloads exceeding `-RetentionDays` (default: 30 days), preventing runaway cloud storage billing. Includes `-DryRun` preview mode.
    - **GKE Health Diagnostics:** `-Action status` retrieves master version, node pool counts, and cluster provisioning status.
  - **Syntax & Parameters:**
    ```powershell
    .\scripts\cloud\gcp\manage-gcp.ps1 [-Action all|deploy|login|credentials|disk-cleanup|status] [-Environment dev|staging|prod] [-GcpRegion <reg>] [-GcpProject <proj>] [-ClusterName <cluster>] [-RetentionDays <days>] [-DryRun]
    ```
  - **Examples:**
    ```powershell
    # Full deployment to GKE Staging (GAR login + GKE credentials + Helm deploy):
    .\scripts\cloud\gcp\manage-gcp.ps1 -Action all -Environment staging

    # Authenticate Docker CLI with Google Artifact Registry:
    .\scripts\cloud\gcp\manage-gcp.ps1 -Action login -GcpRegion us-central1

    # Deploy microservices to GKE Production:
    .\scripts\cloud\gcp\manage-gcp.ps1 -Action deploy -Environment prod

    # FinOps: Audit and purge disk snapshots older than 14 days (Preview mode):
    .\scripts\cloud\gcp\manage-gcp.ps1 -Action disk-cleanup -Environment prod -RetentionDays 14 -DryRun

    # FinOps: Execute live purge of orphaned snapshots:
    .\scripts\cloud\gcp\manage-gcp.ps1 -Action disk-cleanup -Environment prod -RetentionDays 30

    # Display GKE cluster and node status:
    .\scripts\cloud\gcp\manage-gcp.ps1 -Action status -Environment staging
    ```

### 6. `scripts/cloud/cloudflare/` (Zero-Trust Tunnels)
- **`start-cloudflare-tunnels.ps1`**: Launches Cloudflare Zero-Trust tunnels to expose services securely without opening inbound ports.

### 7. `scripts/istio/` (Service Mesh & Traffic Management)
- **`set-canary-weight.ps1`**: Dynamically adjusts traffic splitting weights (e.g., 90/10, 50/50, 0/100) on Istio VirtualServices.
- **`auto-canary-rollout.ps1`**: Automated progressive canary deployment controller that promotes v2 after verifying error rates remain < 1%.
- **`verify-mesh.ps1`**: Validates strict mTLS enforcement and sidecar proxy injection across microservices.

### 8. `scripts/auth/` & `scripts/vault/` (Identity & Secrets Provisioning)
- **`scripts/auth/bootstrap-keycloak.ps1`**: Configures Keycloak realm `microservices-realm`, OIDC clients (`angular-client`, `gateway-client`), and default `ROLE_USER`.
- **`scripts/vault/init-vault.ps1`**: Initializes HashiCorp Vault, enables KV-v2 and Transit engines, seeds secrets, and applies least-privilege policies.

### 9. `scripts/build/` (Build & Release Automation)
- **`build-all.py`**: Concurrently builds all Java microservices (Maven clean package) and Angular frontend (npm build).
- **`deploy-helm.ps1`**: Deploys the unified umbrella Helm chart to Kubernetes with environment-specific values.
- **`push-all.ps1`**: Tags and pushes container images to remote registries (Docker Hub, ECR, ACR, GAR).
- **`update_dashboards.py`**: Formats and synchronizes Grafana dashboard JSON models.
- **`generate_drawio.py`**: Programmatically generates the 12-page architectural blueprint in [`docs/Diagrams.drawio`](./Diagrams.drawio).

### 10. `scripts/testing/` (Enterprise Testing & Simulation Super-Scripts)
- **`simulate.py`**: **Unified Simulation Engine** with:
  - `--scenario traffic`: E-commerce shopping journey, Keycloak JWT auth, cart additions, orders, and Kafka events.
  - `--scenario ddos`: High-concurrency 12-IP botnet request flood and Redis rate-limit (HTTP 429) stress.
  - `--scenario chaos`: Stock exhaustion, circuit breaker tripping, invalid SKUs, and fault tolerance.
  - `--scenario all`: Full end-to-end load, DDoS, and chaos drill.
- **`smoke.py`**: **Unified E2E Smoke Testing Engine**:
  - Validates API Gateway and microservice `/actuator/health` probes.
  - Queries product catalog with latency SLO assertions (< 500ms).
  - Tests authenticated order creation with Idempotency UUIDs.
  - Enforces negative security boundary (asserts 401/403 on unauthenticated routes).
- **`verify.py`**: **Platform Component Verification**:
  - `--target swagger`: Validates Swagger UI and OpenAPI 3.0 documentation across all services.
  - `--target metrics`: Queries Prometheus label names and active e-commerce / system series.
  - `--target grafana`: Audits Grafana dashboards (`business-operations`, `technical-security`) and panels.
- **`check.py`**: **Diagnostic Telemetry & PromQL Evaluator**:
  - `--check jvm`: Inspects JVM heap memory, live threads, and CPU usage.
  - `--check abandonment`: Evaluates real-time cart abandonment PromQL calculations.
  - `--check vault`: Verifies HashiCorp Vault unsealed status and scrape health.
  - `--check promql --query "<expr>"`: Evaluates arbitrary PromQL expressions with formatted series output.

---

