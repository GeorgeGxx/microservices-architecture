# 📄 ADR-012: Dual AWS Production Dataplane Topology and Blast-Radius Containment

* **Status:** 🟢 ACCEPTED
* **Deciders:** Principal Cloud Platform Architect, Senior DevSecOps Engineer, Kubernetes Security Specialist, Lead SRE
* **Date:** 2026-10-31
* **Technical Story:** Production Resilience, Multi-Cluster High Availability, and Dataplane Failure Domain Isolation

---

## 🎯 Context & Problem Statement

Production cloud environments running critical enterprise workloads require high availability, disaster resilience, and blast-radius containment. A single Kubernetes cluster represents a shared failure domain: control plane API degradation, Kubernetes version upgrades, node group rolling updates, CNI network disruptions, or cluster-scoped misconfigurations can cause widespread outages.

To guarantee operational resilience, the production architecture must operate **two independent AWS EKS dataplanes** (`msa-aws-prod` as Dataplane 1 and `msa-aws-dp2-prod` as Dataplane 2), while dev and staging maintain single clusters.

---

## 🏗️ Architecture & Topology Breakdown

### 1. Cluster Identity & Control Plane Independence
- **Dataplane 1 (DP1 - Primary):**
  - EKS Cluster: `msa-aws-prod`
  - Control Plane: Dedicated AWS-managed Kubernetes control plane with independent API endpoint and CloudWatch audit logging (`api`, `audit`, `authenticator`, `controllerManager`, `scheduler`).
  - Compute: Dedicated managed node group (`m6i.large`, ON_DEMAND, multi-AZ).
  - IAM & OIDC: Independent IAM cluster role, node role, and OIDC provider for IRSA (`irsa_lb_controller`).
  - GitOps: Argo CD application `microservices-prod` targeting `https://kubernetes.default.svc`.
- **Dataplane 2 (DP2 - Secondary):**
  - EKS Cluster: `msa-aws-dp2-prod` (provisioned conditionally via `count = local.env == "prod" ? 1 : 0`).
  - Control Plane: Independent AWS-managed control plane, independent API endpoint, and independent CloudWatch audit logging.
  - Compute: Dedicated managed node group (`m6i.large`, ON_DEMAND, multi-AZ, tagged with `DataPlane = "2"`).
  - IAM & OIDC: Independent IAM cluster role, node role, and distinct OIDC provider (`irsa_lb_controller_dp2`).
  - GitOps: Argo CD application `microservices-prod-dp2` targeting registered destination cluster `msa-aws-dp2-prod`.

### 2. Shared vs Independent Infrastructure Boundary

| Component | Architecture Type | Justification & Blast-Radius Boundary |
| :--- | :--- | :--- |
| **AWS VPC & Subnets** | Shared | Shared VPC CIDR (`10.20.0.0/16`) and multi-AZ private subnets reduce routing complexity and inter-VPC peering overhead. |
| **EKS Control Plane** | **Independent** | DP1 and DP2 have completely decoupled etcd clusters and API servers. A failure in DP1 API server does not affect DP2. |
| **EKS Node Groups** | **Independent** | Independent EC2 Auto Scaling groups and launch templates with IMDSv2. Rolling upgrades occur sequentially (DP1 then DP2). |
| **IAM OIDC & IRSA** | **Independent** | Dedicated OIDC identity providers ensure pod identities in DP1 cannot impersonate or assume roles reserved for DP2. |
| **RDS PostgreSQL** | Shared Managed | AWS RDS PostgreSQL Multi-AZ (`db.t3.medium`) with automated failover across AZs, KMS customer encryption, and security group ingress restricted to DP1 and DP2 node groups. |
| **ElastiCache Redis** | Shared Managed | Redis 7 cluster with Multi-AZ automatic failover, in-transit encryption, KMS at-rest encryption, accessible by both dataplanes. |
| **Amazon MSK Kafka** | Shared Managed | 3-broker multi-AZ Kafka cluster with TLS encryption, accessible only by DP1 and DP2 worker nodes. |
| **Perimeter Ingress** | Coordinated | Layer 4 NLB and CloudFront edge routing distribute incoming traffic across the Istio Ingress Gateways of both dataplanes. |
| **GitOps Continuous Delivery** | **Independent** | Argo CD governs `microservices-prod` and `microservices-prod-dp2` as separate Applications, allowing phased progressive promotion and independent rollbacks. |

---

## 🛡️ Failure Isolation & Operational Implications

1. **Kubernetes Version Lifecycle:**
   - Kubernetes minor version upgrades (e.g., 1.30 $\rightarrow$ 1.31) can be tested on DP2 first, verified with live synthetic traffic, before applying to DP1.
2. **Blast-Radius Containment:**
   - A catastrophic node group crash or CNI subnet exhaustion in DP1 leaves DP2 fully operational to absorb production workload demands.
3. **Rollback Resilience:**
   - If an application update degrades service on DP1, Argo CD and CI/CD can immediately shift ingress routing to DP2 while rolling back DP1.
4. **Data Consistency:**
   - State remains consolidated and synchronized in shared multi-AZ managed data stores (RDS PostgreSQL with ACID transactions, MSK Kafka with distributed commit logs, ElastiCache Redis for distributed caching).

---

## 💡 Decision Outcome

**Decision:** **Preserve and strictly maintain both AWS production dataplanes.**

Never consolidate DP1 and DP2 into a single cluster. All Terraform modifications, GitOps manifests, and security policies must support both clusters with consistent hardening (IMDSv2, control plane logging, strict mTLS, least-privilege RBAC).
