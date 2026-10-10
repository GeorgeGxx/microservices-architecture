# 📄 ADR-009: Modular Multi-Cloud Infrastructure as Code with HashiCorp Terraform

* **Status:** 🟢 ACCEPTED
* **Deciders:** Enterprise Architect, Platform/DevOps Lead, Cloud Architect
* **Date:** 2026-03-15
* **Technical Story:** Multi-Cloud Infrastructure as Code & Provider Abstraction

---

## 🎯 Context & Problem Statement

Deploying microservices across multiple cloud environments (AWS, Azure, GCP) and local development (Minikube) using cloud-native vendor-specific templates (AWS CloudFormation, Azure Bicep, Google Deployment Manager) leads to duplicated codebases, fragmented CI/CD pipelines, steep learning curves, and vendor lock-in.

We require an Infrastructure as Code (IaC) framework that:
1. Provisions Kubernetes clusters and supporting cloud services across AWS (EKS), Azure (AKS), GCP (GKE), and Minikube.
2. Promotes reusable, modular design across development, staging, and production tiers.
3. Integrates with remote state storage and distributed state locking.
4. Supports automated security scanning in CI/CD pipelines (via Checkov / Trivy).

---

## ⚖️ Decision Drivers

1. **Multi-Cloud Portability:** Unified HCL syntax across all target cloud providers.
2. **State Management & Locking:** Strong concurrency controls (S3/DynamoDB, Azure Blob, GCS) preventing race conditions.
3. **Ecosystem & Module Maturity:** Vast community and official provider registry.
4. **DevSecOps Pipeline Integration:** Automated `validate`, `fmt`, `plan`, and policy-as-code linting.

---

## 🔍 Considered Alternatives

* **Option 1 (Baseline):** Cloud-Native Templates (CloudFormation + Bicep + Google Deployment Manager)
* **Option 2:** HashiCorp Terraform / OpenTofu (HCL Modular Architecture)
* **Option 3:** Pulumi (General Purpose Programming Languages: TS/Python/Go)

---

## 📊 Pugh Multi-Criteria Decision Matrix

| Evaluation Criteria | Weight (1-5) | Option 1: Vendor Templates | Option 2: Terraform (HCL) | Option 3: Pulumi |
| :--- | :---: | :---: | :---: | :---: |
| **Multi-Cloud Unified Language** | 5 | 0 (Baseline: fragmented) | **+1** (Single language: HCL) | +1 (TypeScript/Go/Python) |
| **Declarative State & Plan Diffs** | 5 | 0 (Baseline) | **+1** (Predictable `terraform plan`) | +1 (Plan diffs) |
| **Security Scanning Ecosystem (Checkov)** | 4 | 0 (Baseline) | **+1** (Industry standard for static IaC scan) | 0 (Less mature rulesets) |
| **Developer Onboarding & Adoption** | 4 | 0 (Baseline: 3 different stacks) | **+1** (High global adoption) | 0 (Programming language fragmentation) |
| **Weighted Total** | - | **0.00** | **+18 (WINNER)** | +10.00 |

---

## 💡 Decision Outcome

Chosen option: **Option 2 (HashiCorp Terraform)**.

The repository organizes Terraform into a clean modular architecture:
* `terraform/environments/local-minikube/`: Local development cluster configuration.
* `terraform/environments/aws/`: EKS, VPC, RDS, and S3 backend.
* `terraform/environments/azure/`: AKS, VNet, Azure Database, and Blob storage.
* `terraform/environments/gcp/`: GKE, VPC, Cloud SQL, and GCS backend.

### Positive Consequences
* **Decoupled entrypoints:** `platform-multicloud.ps1` (`-Provider aws|azure|gcp`) drives Terraform across cloud providers without cascading scripts; `platform-minikube.ps1` manages the local zero-cost cluster.
* **Shift-Left IaC Security:** Validated in CI/CD using Checkov and Trivy before any infrastructure changes are applied.
