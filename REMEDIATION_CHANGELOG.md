# Multi-Cloud Architecture Audit & Controlled Remediation Changelog

## Summary of Remediations Executed (`2026-10-30`)

### 1. `P0` — Multi-Cloud Terraform & Production Dual-Dataplane Remediations

- **AWS (`terraform/environments/aws/main.tf`, `outputs.tf`, `terraform/modules/aws/oidc_github/*`, `terraform/modules/aws/ecr/variables.tf`):**
  - Updated `allowed_security_group_ids` on `module.rds_postgres`, `module.elasticache_redis`, and `module.msk_kafka` to include both `module.eks.node_security_group_id` and `try(module.eks_dp2[0].node_security_group_id, null)`.
  - Added `module.irsa_lb_controller_dp2` (`count = local.env == "prod" ? 1 : 0`) and exported `irsa_lb_controller_role_arn` and `production_dataplane_2_irsa_lb_controller_role_arn`.
  - Hardened `terraform/modules/aws/oidc_github/main.tf` and `variables.tf` to scope OIDC subject claims by environment (`refs/heads/develop`, `refs/heads/staging`, `refs/heads/prod`, and `environment:<env>`) instead of wildcard `*`, supporting both `GeorgeGxx/microservices-architecture` and `georgegxx/microservices-architecture`.
  - Added `"payments-service"`, `"fulfillment-service"`, `"analytics-service"`, and `"mlops-training"` to `terraform/modules/aws/ecr/variables.tf`.
- **Azure (`terraform/environments/azure/main.tf`, `locals.tf`, `versions.tf`, `outputs.tf`, `terraform/modules/azure/frontdoor/*`):**
  - Added `azurerm_role_assignment.aks_dp2_acr` (`AcrPull`), `azurerm_role_assignment.aks_dp2_secrets_reader` (`Key Vault Secrets User`), `module.workload_identity_dp2`, and `azurerm_public_ip.istio_gateway_dp2_public_ip` for `module.aks_dp2`.
  - Added optional `secondary_api_backend_address` and `azurerm_cdn_frontdoor_origin.api_origin_dp2` to `terraform/modules/azure/frontdoor/` so Azure Front Door balances production API traffic across both `aks` and `aks_dp2`.
  - Added `"ms_payments"`, `"ms_fulfillment"`, and `"ms_analytics"` to `local.database_names` in `terraform/environments/azure/locals.tf`.
  - Hardened `terraform/environments/azure/versions.tf` with `prevent_deletion_if_contains_resources = true` and `purge_soft_delete_on_destroy = false`.
- **GCP (`terraform/modules/gcp/gke/main.tf`, `terraform/modules/gcp/cloudsql/variables.tf`):**
  - Set `deletion_protection = var.environment == "prod"` on `google_container_cluster.this` (protecting both `module.gke` and `module.gke_dp2` in production).
  - Updated `database_names` in `terraform/modules/gcp/cloudsql/variables.tf` to include all polyglot microservice databases (`ms_products`, `ms_inventory`, `ms_orders`, `ms_payments`, `ms_fulfillment`, `ms_analytics`, `keycloak_db`).

### 2. `P1` — Argo CD GitOps & Multi-Cloud CI/CD Pipeline Remediations

- **Argo CD (`argocd/appproject.yaml`, `argocd/application-prod.yaml`, `argocd/application-prod-dp2.yaml`):**
  - Replaced wildcards in `argocd/appproject.yaml` with explicit source repositories, cluster destinations (`https://kubernetes.default.svc` and `msa-aws-dp2-prod`), and Kubernetes resource whitelists.
  - Updated `argocd/application-prod.yaml` from `targetRevision: main` to `targetRevision: prod`.
  - Created `argocd/application-prod-dp2.yaml` tracking `targetRevision: prod` for the secondary production EKS dataplane (`msa-aws-dp2-prod`).
- **Azure DevOps (`azure-devops/templates/*`, `azure-devops/pipelines/*`):**
  - Aligned all pipelines and templates with `develop` $\rightarrow$ `staging` $\rightarrow$ `prod`.
  - Updated `azure-devops/pipelines/infra.yml` and `azure-devops/templates/infra-stages.yml` with production destructive-plan guards and dual-dataplane namespace provisioning.
  - Updated `azure-devops/templates/app-stages.yml` and `azure-devops/templates/steps/helm-deploy.yml` to promote immutable `@sha256` digests without rebuilding and deploy/rollback across both `msa-azure-prod-aks` (`DP1`) and `msa-azure-dp2-prod-aks` (`DP2`).
- **Bitbucket Pipelines (`bitbucket-pipelines.yml`):**
  - Fixed `BITBUCKET_DEPLOYMENT_ENVIRONMENT` (`dev|test)`), added `prod` branch pipeline, enabled GCP OIDC Workload Identity Federation (`BITBUCKET_STEP_OIDC_TOKEN`) with `GCP_SA_KEY` fallback, enforced immutable digest promotion, and configured dual-dataplane GKE deployment and verification (`$GKE_CLUSTER_NAME` + `${GKE_CLUSTER_NAME_DP2:-msa-gcp-dp2-prod-cluster}`).
- **GitHub Actions (`.github/workflows/*`):**
  - Updated all `service-*.yml`, `security-scan.yml`, `local-quality-gates.yml`, and `helm-chart-release.yml` workflows to align with `develop`, `staging`, and `prod`.
  - Added production dual-dataplane destructive-change guard to `.github/workflows/terraform-aws.yml`.
  - Updated `.github/workflows/_service-ci-cd-template.yml` to promote immutable digests on `staging`/`prod`, remove hardcoded `--insecure` when TLS is active, and sync/rollback both `microservices-prod` and `microservices-prod-dp2`.

### 3. `P2` — Helm Values & Static Verification

- Created `helm/values/values-aks-staging.yaml`, `helm/values/values-gke-staging.yaml`, and `helm/values/values-gke-prod.yaml`.
- Verified `terraform fmt -check -recursive`, `terraform validate` across AWS, Azure, and GCP, and `helm lint` across all 7 environment value files with 0 errors.
