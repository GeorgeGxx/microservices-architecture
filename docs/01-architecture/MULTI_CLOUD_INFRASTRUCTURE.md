# ☁️ Multi-Cloud Terraform Infrastructure & Recovery Guide

> [!TIP]
> 🧭 **[Enterprise Platform Hub](../../README.md)** > **01. Architecture** > `MULTI_CLOUD_INFRASTRUCTURE.md`

> Architecture specification for AWS (EKS / RDS / VPC), Azure (AKS / PostgreSQL / KeyVault), and GCP (GKE / CloudSQL / Memorystore), including environment-isolated Terraform state and application recovery procedures.

---

## 🔄 Multi-Cloud Recovery & Rollback Procedures

Universal Helm atomic rollbacks, GitOps automated reconciliation (ArgoCD), and provider-specific rollback runbooks across GitHub Actions, Azure DevOps, and Bitbucket Pipelines are consolidated in the canonical [Business Continuity & Disaster Recovery Strategy (Runbook 6: Application Release Rollback)](./DISASTER_RECOVERY_STRATEGY.md#runbook-6-application-release-rollback-helm-gitops--multi-cicd).

---

## ☁️ Terraform Multi-Cloud Infrastructure (AWS, Azure, GCP)

### Cluster and workspace topology

The target topology is **12 Kubernetes clusters**: four for each provider. Each
provider root keeps the same three Terraform workspaces (`dev`, `staging`,
`prod`); the `prod` workspace provisions two independent clusters/data planes.
This avoids treating the two production clusters as separate environments or
duplicating shared databases, networking, and edge resources.

| Provider | `dev` workspace | `staging` workspace | `prod` workspace | Total |
| --- | --- | --- | --- | ---: |
| AWS | `msa-aws-dev` | `msa-aws-staging` | `msa-aws-prod`, `msa-aws-dp2-prod` | 4 |
| Azure | `msa-azure-dev-aks` | `msa-azure-staging-aks` | `msa-azure-prod-aks`, `msa-azure-dp2-prod-aks` | 4 |
| GCP | `msa-gcp-dev-cluster` | `msa-gcp-staging-cluster` | `msa-gcp-prod-cluster`, `msa-gcp-dp2-prod-cluster` | 4 |

The second production cluster has independent Kubernetes control plane and
worker capacity. AWS shares the environment VPC/subnets; Azure receives a
dedicated AKS subnet; GKE receives dedicated secondary Pod/Service ranges and a
separate control-plane CIDR. Supporting databases and shared edge services
remain provisioned once per environment workspace.

Create/select the three workspaces independently in each provider root before
planning. For example:

```powershell
foreach ($provider in @('aws', 'azure', 'gcp')) {
  Push-Location "terraform/environments/$provider"
  terraform workspace new dev 2>$null; terraform workspace select dev
  terraform workspace new staging 2>$null; terraform workspace select staging
  terraform workspace new prod 2>$null; terraform workspace select prod
  Pop-Location
}
```

Each provider root uses the same workspace names: `dev`, `staging`, and `prod`.
- **AWS (S3 Backend):** Uses `bucket`, `key`, and `dynamodb_table` alongside native S3 object lockfiles (`use_lockfile = true`, introduced in Terraform 1.10+). This gives double-guarded distributed concurrency control across GitHub Actions and `platform-multicloud.ps1 -Provider aws`.
- **Azure (Azurerm Backend):** Uses Azure Blob Storage with automated, native **Blob Leases**. The lease is acquired upon state read/write and released automatically without needing external lock tables or auxiliary parameters.
- **Google Cloud (GCS Backend):** Uses Google Cloud Storage with automated, native **Generation Preconditions** (`x-goog-if-generation-match: 0`). Atomic object creation and locking are built directly into GCS without requiring third-party state locks.

Before running Azure/GCP cloud commands, provision their state stores and copy/fill the ignored partial-backend files:

```powershell
Copy-Item terraform/backend-config/azure.hcl.example terraform/backend-config/azure.hcl
Copy-Item terraform/backend-config/gcp.hcl.example terraform/backend-config/gcp.hcl
```

The example files contain placeholders and are not ready for use until you
replace them with real storage identifiers. Do not commit the filled files.
The new backend declarations do not migrate existing local state. If you have
state already in use, back it up and plan a deliberate `terraform init
-migrate-state` for each provider/workspace before any cloud plan or apply.
Terraform initialization and plans were not run against cloud credentials as
part of this code change. Review all production plans and costs before apply.

### 1. AWS Provider (Amazon EKS / RDS / VPC)
Located in `terraform/environments/aws/` and `terraform/modules/aws/`:
```powershell
cd terraform/environments/aws
terraform init
terraform workspace select staging || terraform workspace new staging
terraform plan -var-file=staging/terraform.tfvars
terraform apply -var-file=staging/terraform.tfvars
```

### 2. Azure Provider (Azure AKS / ACR / PostgreSQL)
Located in `terraform/environments/azure/` and `terraform/modules/azure/`:
```powershell
cd terraform/environments/azure
terraform init -backend-config=../../backend-config/azure.hcl
terraform workspace select staging || terraform workspace new staging
terraform plan -var-file=staging/terraform.tfvars
terraform apply -var-file=staging/terraform.tfvars
```

### 3. GCP Provider (Google GKE / Artifact Registry / Cloud SQL)
Located in `terraform/environments/gcp/` and `terraform/modules/gcp/`:
```powershell
cd terraform/environments/gcp
terraform init -backend-config=../../backend-config/gcp.hcl
terraform workspace select staging || terraform workspace new staging
terraform plan -var-file=staging/terraform.tfvars
terraform apply -var-file=staging/terraform.tfvars
```

---

## ☁️ Multi-Cloud Terraform 12-Module Matrix (AWS • Azure • GCP)

The infrastructure layer in `terraform/` provides **100% architectural parity** across Amazon Web Services, Microsoft Azure, and Google Cloud Platform for environments **`dev`**, **`staging`**, and **`prod`**:

```text
terraform/
├── environments/
│   ├── aws/       (locals.tf, main.tf, outputs.tf, variables.tf)
│   ├── azure/     (locals.tf, main.tf, outputs.tf, variables.tf)
│   └── gcp/       (locals.tf, main.tf, outputs.tf, variables.tf)
└── modules/
    ├── aws/       (cloudfront, cloudwatch, ecr, eks, elasticache, iam-irsa, kms, msk, nlb, oidc_github, rds, route53_acm, s3, s3-backend, vpc)
    ├── azure/     (acr, aks, dns_zone, eventhubs, frontdoor, keyvault, monitor, postgresql, redis, storage_account, vnet, workload_identity)
    └── gcp/       (cloud_armor_lb, cloud_cdn, cloud_dns, cloud_monitoring, cloudsql, gar, gcs, gke, kms, managed_kafka, memorystore, vpc, workload_identity)
```

| Architectural Layer | AWS Native Module | Azure Native Module | GCP Native Module |
| :--- | :--- | :--- | :--- |
| **1. VPC / Networking** | `modules/aws/vpc` | `modules/azure/vnet` | `modules/gcp/vpc` |
| **2. Kubernetes (K8s)** | `modules/aws/eks` | `modules/azure/aks` | `modules/gcp/gke` |
| **3. Relational Database** | `modules/aws/rds` | `modules/azure/postgresql` | `modules/gcp/cloudsql` |
| **4. Redis Cache** | `modules/aws/elasticache` | `modules/azure/redis` | `modules/gcp/memorystore` |
| **5. Event Streaming (Kafka)** | `modules/aws/msk` | `modules/azure/eventhubs` | `modules/gcp/managed_kafka` |
| **6. Object Storage** | `modules/aws/s3` | `modules/azure/storage_account` | `modules/gcp/gcs` |
| **7. KMS / Key Management** | `modules/aws/kms` | `modules/azure/keyvault` | `modules/gcp/kms` |
| **8. Workload Identity (IRSA)** | `modules/aws/iam-irsa` | `modules/azure/workload_identity` | `modules/gcp/workload_identity` |
| **9. L4 Ingress / Gateway Target** | `modules/aws/nlb` | `modules/azure/vnet` (AKS SLB) | `modules/gcp/cloud_armor_lb` |
| **10. CDN & Edge Perimeter (L7)** | `modules/aws/cloudfront` | `modules/azure/frontdoor` | `modules/gcp/cloud_cdn` |
| **11. Observability & Alarms** | `modules/aws/cloudwatch` | `modules/azure/monitor` | `modules/gcp/cloud_monitoring` |
| **12. DNS & Certificates** | `modules/aws/route53_acm` | `modules/azure/dns_zone` | `modules/gcp/cloud_dns` |

---

## ☁️ Active AWS Production-Environment Architecture

The platform provides a fully production-grade, hardened **Amazon Web Services (AWS)** deployment topology that is actively maintained and integrated across our IaC, Helm, GitOps, and CI/CD pipelines.

### Active AWS Platform Components

#### Managed data-streaming version alignment

The local `confluentinc/cp-kafka:8.3.2` image is Confluent Platform 8.3.2 and bundles Apache Kafka 4.3.x; its tag is not an Apache Kafka version. The Terraform MSK module provisions standard (non-Express) brokers, for which AWS currently supports Kafka 4.1.x as the closest available line. MSK Kafka 4.2.x is Express-only, so Terraform uses `4.1.x` until the module explicitly adopts Express brokers. This is the closest managed-service mapping, not a same-version deployment; validate client compatibility and feature use when promoting between environments. Kafka 4.x uses KRaft, so the Terraform module uses an M5 broker because AWS does not support T3 brokers with KRaft. For an existing ZooKeeper-based MSK cluster, check AWS's supported migration path and compatible target versions before applying Terraform; the version change alone is not a safe migration plan. See [Confluent's compatibility matrix](https://docs.confluent.io/platform/current/installation/versions-interoperability.html), [AWS MSK supported versions](https://docs.aws.amazon.com/msk/latest/developerguide/supported-kafka-versions.html), [AWS MSK version upgrades](https://docs.aws.amazon.com/msk/latest/developerguide/version-upgrades.html), and [AWS MSK broker sizes](https://docs.aws.amazon.com/msk/latest/developerguide/broker-instance-sizes.html).

ElastiCache remains on Redis OSS 7.1, currently AWS's newest Redis OSS engine version. ElastiCache's newer Valkey releases use a distinct engine and require a compatibility/migration decision rather than a Redis version bump. See [AWS ElastiCache engine versions](https://docs.aws.amazon.com/AmazonElastiCache/latest/dg/engine-versions.html).

* **Terraform Infrastructure as Code ([`terraform/environments/aws/`](../../terraform/environments/aws/)):**
  * Modular multi-environment workspaces: `dev`, `staging`, and `prod`.
  * Backed by production-grade modules in [`terraform/modules/aws/`](../../terraform/modules/aws/):
    * **VPC & Networking:** Multi-AZ public/private subnets, NAT Gateways, Route Tables.
    * **EKS Cluster:** Managed node groups, IMDSv2 enforced, encrypted secrets with AWS KMS.
    * **IAM & Zero-Trust:** GitHub Actions OIDC identity federation (zero static access keys) and IRSA (IAM Roles for Service Accounts).
    * **Ingress & Security:** AWS Load Balancer Controller (ALB), ACM TLS certificates, AWS WAFv2 WebACL.
    * **Storage:** EBS CSI Driver with high-IOPS `gp3` storage class.
    * **Frontend & CDN:** S3 bucket with Origin Access Control (OAC) and CloudFront TLS 1.3 distribution.
    * **FinOps:** Native AWS budget alert policies (`finops.tf`).

* **Hardened Helm Values ([`helm/values/`](../../helm/values/)):**
  * [`values-eks-dev.yaml`](../../helm/values/values-eks-dev.yaml), [`values-eks-staging.yaml`](../../helm/values/values-eks-staging.yaml), and [`values-eks-prod.yaml`](../../helm/values/values-eks-prod.yaml).
  * Injects ALB Ingress annotations, ACM certificate ARNs, and External Secrets Operator (ESO) integration with AWS Secrets Manager.

* **GitOps Continuous Delivery ([`argocd/`](../../argocd/)):**
  * Multi-environment declarative applications ([`application-dev.yaml`](../../argocd/application-dev.yaml), [`application-staging.yaml`](../../argocd/application-staging.yaml), [`application-prod.yaml`](../../argocd/application-prod.yaml)) configured with automated self-healing, prune policies, and health monitoring.

* **Automated CI/CD Delivery ([`.github/workflows/`](../../.github/workflows/)):**
  * [`.github/workflows/terraform-aws.yml`](../../.github/workflows/terraform-aws.yml) for automated Terraform plan/apply workflows.
  * [`.github/workflows/_service-ci-cd-template.yml`](../../.github/workflows/_service-ci-cd-template.yml) for automated service build, blocking CRITICAL image scan, Git SHA image publication to Docker Hub, digest-based GitOps deployment, and conditional post-deployment checks. The current reusable workflow does not publish to ECR; registry-specific cloud promotion remains a separate configuration task.

### 🛠️ AWS Deployment & Operational Workflow

#### 1. Zero-Trust AWS IAM OIDC Authentication
GitHub Actions assumes roles via AWS STS Web Identity Tokens:
* Audience: `sts.amazonaws.com`
* Provider URL: `https://token.actions.githubusercontent.com`
* Repository Secret: `AWS_ROLE_ARN`

#### 2. Provisioning Infrastructure via Multi-Cloud CLI
Deploy AWS VPC, EKS, ECR, and supporting services using [`platform-multicloud.ps1`](../../platform-multicloud.ps1):
```bash
# Validate and provision AWS staging infrastructure
./platform-multicloud.ps1 apply-infra -Provider aws -Environment staging

# Apply Kubernetes workloads through Helm
./platform-multicloud.ps1 apply-workloads -Provider aws -Environment staging

# Trigger ArgoCD GitOps reconciliation
./platform-multicloud.ps1 sync-argocd -Provider aws -Environment staging
```

#### 3. Post-Deployment Verification & Security Gates
Following deployment, automated test suites execute against the live AWS EKS endpoint:
* Newman API contract test suite (23/23 endpoints pass).
* k6 resilience & SLO load benchmark (p95 < 200 ms).
* OWASP ZAP baseline dynamic application security scan (DAST).

---

## 🔍 AWS Active Resource Discovery Tool (`scripts/cloud/aws/aws_active_resources_list.py`)

For multi-region governance, auditing active workloads, and verifying decommissioned environments across an AWS account, the platform provides a standalone Boto3 scanner:

```bash
# Query a single service in a specific region
python scripts/cloud/aws/aws_active_resources_list.py us-east-1 ec2

# Query all regions for a service
python scripts/cloud/aws/aws_active_resources_list.py all ec2 [profile]

# Scan matrix across all 12 services and regions (tabular summary)
python scripts/cloud/aws/aws_active_resources_list.py all all [profile]
python scripts/cloud/aws/aws_active_resources_list.py us-east-1 all [profile]
```

Supported services:
- **Regional (9):** `ec2`, `vpc`, `lambda`, `glue` (jobs & crawlers), `cloudformation`, `kms`, `sns`, `sqs`, `ebs`.
- **Global (3):** `s3`, `iam`, `route53` (queried once globally).

Outputs a concise ASCII table indicating active resources (`✓`), empty state (`-`), un-enabled regions (`opt`), or permission/network errors (`ERR`), followed by an execution summary.

---
