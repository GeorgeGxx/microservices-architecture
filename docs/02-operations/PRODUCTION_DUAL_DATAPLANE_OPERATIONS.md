# Production Dual-Dataplane Operations Guide (AWS, Azure & GCP)

## 1. Architectural Invariant

> **Production Dual-Dataplane Mandate:**
> `DEV` and `STAGING` operate a single Kubernetes dataplane per cloud provider.
> `PRODUCTION` operates **two independent Kubernetes dataplanes (`DP1` and `DP2`)** per cloud provider. Both dataplanes must remain active, healthy, and synchronized to the exact same immutable artifact digest.

| Cloud Provider | Primary Production Dataplane (`DP1`) | Secondary Production Dataplane (`DP2`) | Shared Stateful Backends | Edge Traffic Distribution |
|---|---|---|---|---|
| **AWS** | `module.eks` (`msa-aws-prod`) | `module.eks_dp2` (`msa-aws-dp2-prod`) | Multi-AZ RDS PostgreSQL 18, Multi-AZ ElastiCache Redis, 3-Broker MSK Kafka | Route 53 + CloudFront + NLB fronting Istio Gateways |
| **Azure** | `module.aks` (`msa-azure-prod-aks` in `10.60.0.0/20`) | `module.aks_dp2` (`msa-azure-dp2-prod-aks` in `10.60.32.0/20`) | Zone-Redundant PostgreSQL 18 Flexible Server, Premium Redis, Event Hubs | Azure Front Door Premium + WAF (`api_origin` + `api_origin_dp2`) |
| **GCP** | `module.gke` (`msa-gcp-prod-cluster` in `10.41.0.0/16`) | `module.gke_dp2` (`msa-gcp-dp2-prod-cluster` in `10.43.0.0/16`) | Regional HA Cloud SQL PostgreSQL 18, HA Memorystore Redis, Managed Kafka | Cloud Armor + Global External Load Balancer + Cloud CDN |

---

## 2. Targeted Terraform Operations for Production Dataplanes

### AWS (`terraform/environments/aws`)

- **Plan/Apply Both Dataplanes & Shared Infrastructure:**
  - GitHub Actions `terraform-aws.yml` workflow input: `environment: prod`, `data_plane: all`.
- **Target Primary Dataplane Only (`DP1`):**
  - `data_plane: primary` (`-target=module.eks -target=module.irsa_lb_controller`).
- **Target Secondary Dataplane Only (`DP2`):**
  - `data_plane: secondary` (`-target=module.eks_dp2 -target=module.irsa_lb_controller_dp2`).

### Azure (`terraform/environments/azure`) & GCP (`terraform/environments/gcp`)

Both `module.aks_dp2` and `module.gke_dp2` are gated by `count = local.env == "prod" ? 1 : 0` and are automatically planned, validated, and protected against accidental deletion when the `prod` Terraform workspace is selected.

---

## 3. Dual-Dataplane Application Release & Drain Runbook

1. **Sequential Rollout (`DP1` $\rightarrow$ `DP2`):**
   - **Azure DevOps (`azure-devops/templates/app-stages.yml`):** Executes `HelmCanaryProductionDP1` (`msa-azure-prod-aks`) followed by `HelmCanaryProductionDP2` (`msa-azure-dp2-prod-aks`).
   - **Bitbucket Pipelines (`bitbucket-pipelines.yml`):** Iterates over `TARGET_CLUSTERS=("$GKE_CLUSTER_NAME" "${GKE_CLUSTER_NAME_DP2:-msa-gcp-dp2-prod-cluster}")` and verifies `kubectl rollout status` on each cluster.
   - **GitHub Actions + Argo CD (`.github/workflows/_service-ci-cd-template.yml`):** Synchronizes and waits for health on `microservices-prod` (`DP1`) followed by `microservices-prod-dp2` (`DP2`).
2. **Maintenance Drain of One Dataplane:**
   - Because edge load balancers (Azure Front Door `api_group` health probes on `/actuator/health`, AWS NLB/Route 53 health checks, and GCP Cloud Armor LB health checks) continuously probe both dataplanes, cordoning or draining one dataplane for Kubernetes minor version upgrades shifts 100% of live traffic to the healthy sibling dataplane with zero downtime.
