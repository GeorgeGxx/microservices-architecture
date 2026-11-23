# Multi-Cloud Terraform Governance & State Management

## 1. Remote Backend & State Locking Architecture

Each cloud provider uses an isolated, encrypted remote backend with native state locking and workspace isolation (`dev`, `staging`, `prod`):

| Cloud Provider | Root Module | Backend Type | Encryption & Locking |
|---|---|---|---|
| **AWS** | `terraform/environments/aws` | `s3` (`georgegxx-msa-tfstate-prod`) | KMS encryption + DynamoDB lock table (`georgegxx-msa-tflock-prod`) |
| **Azure** | `terraform/environments/azure` | `azurerm` (Azure Blob Storage) | Microsoft-managed / Key Vault encryption + native Blob Lease locking |
| **GCP** | `terraform/environments/gcp` | `gcs` (Google Cloud Storage) | Cloud KMS encryption + native GCS object locking |

---

## 2. Workspace-to-Topology Governance

All three cloud roots resolve the active environment from `terraform.workspace` (`dev`, `staging`, `prod`):

- **`dev` Workspace:** Provisions 1 Kubernetes dataplane (`eks`, `aks`, `gke`) with cost-optimized node sizing and in-cluster stateful services for low-cost development.
- **`staging` Workspace:** Provisions 1 Kubernetes dataplane (`eks`, `aks`, `gke`) with managed PostgreSQL 18, managed Redis, managed Kafka/Event Hubs, and WAF/CDN edge routing.
- **`prod` Workspace:** Provisions **2 independent Kubernetes dataplanes** (`eks` + `eks_dp2`, `aks` + `aks_dp2`, `gke` + `gke_dp2`) sharing the production VPC/VNet and managed HA stateful backends with `deletion_protection = true`.

---

## 3. Production Destructive-Change Safeguards

1. **Provider-Level Safeguards:**
   - **AWS:** `deletion_protection = true` and `multi_az = true` on `module.rds_postgres`; `multi_az_enabled = true` on `module.elasticache_redis`; `IMMUTABLE` image tags on `module.ecr`.
   - **Azure:** `prevent_deletion_if_contains_resources = true` on `resource_group` and `purge_soft_delete_on_destroy = false` on `key_vault` in `terraform/environments/azure/versions.tf`; Zone-Redundant HA (`db_ha = true`) on `module.postgresql` with all 7 databases (`ms_products`, `ms_inventory`, `ms_orders`, `ms_payments`, `ms_fulfillment`, `ms_analytics`, `keycloak_db`).
   - **GCP:** `deletion_protection = var.environment == "prod"` on `google_container_cluster.this` (`terraform/modules/gcp/gke/main.tf`) and `prevent_destroy = true` + `REGIONAL` HA preconditions on `google_sql_database_instance.this` (`terraform/modules/gcp/cloudsql/main.tf`).
2. **Pipeline Plan Inspection Gate:**
   - Both `.github/workflows/terraform-aws.yml` and `azure-devops/templates/infra-stages.yml` inspect `terraform show -json tfplan` and block the pipeline if any `delete` action targets primary or secondary production Kubernetes dataplanes (`module.eks`, `module.eks_dp2`, `module.aks`, `module.aks_dp2`) or stateful databases unless `ALLOW_DESTRUCTIVE_TERRAFORM=true` is explicitly set by an authorized platform administrator.

---

## 4. Dedicated CI/CD & DevSecOps Host Tier (`terraform/environments/aws-ec2-compact/`)

To support Jenkins Controller and DevSecOps Worker agents without incurring the overhead of a full multi-node EKS cluster for CI operations, the platform maintains a dedicated compact AWS EC2 environment:

| Environment | Config File | Instance Type | vCPU / RAM | Storage | Primary Purpose |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **`dev`** | `dev.example.tfvars` | `t3.xlarge` | 4 vCPU / 16 GB | 50 GiB GP3 | Jenkins Controller / single-node dev tests |
| **`staging`** | `staging.example.tfvars` | `t3.2xlarge` | 8 vCPU / 32 GB | 80 GiB GP3 | Pre-production DevSecOps verification |
| **`prod`** | `prod.example.tfvars` | `c6i.4xlarge` | 16 vCPU / 32 GB | 120 GiB GP3 | High-throughput concurrent CI/CD builds |

### Key Governance Features:
1. **Dynamic Ansible Inventory Integration**: Generates `ansible/inventory/hosts.ini` dynamically with target groups `[microservices_hosts]`, `[jenkins_controller]`, and `[jenkins_worker]`.
2. **Strict Security Group Ingress**: Restricts SSH (`22`), Jenkins UI (`8080`), and JNLP remoting (`50000`) strictly to the administrator's authorized `admin_cidr`, preventing exposure to the public internet.
3. **Ansible Playbook Automation**: Consumed immediately by `ansible/playbooks/setup-jenkins-controller.yml` and `ansible/playbooks/setup-jenkins-worker.yml` for zero-touch configuration.
