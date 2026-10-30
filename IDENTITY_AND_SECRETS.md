# Identity Federation, Workload Identity & Secrets Governance

## 1. CI/CD Passwordless OIDC Federation

| CI/CD Platform | Cloud Target | Federation Mechanism | Scope & Least-Privilege Controls |
|---|---|---|---|
| **GitHub Actions** | AWS (`sts.amazonaws.com`) | `terraform/modules/aws/oidc_github` (`aws_iam_openid_connect_provider`) | Scoped by environment in `terraform/modules/aws/oidc_github/main.tf` so `prod-github-actions-role` only trusts `repo:GeorgeGxx/microservices-architecture:ref:refs/heads/prod` and `repo:GeorgeGxx/microservices-architecture:environment:prod` (no wildcard `*`). |
| **Azure DevOps** | Azure RM / AKS / ACR | Workload Identity Federation Service Connections (`azure-infra-service-connection`, `azure-service-connection`) | Infra connection is separated from app deployment connection (`AcrPush` + AKS RBAC). |
| **Bitbucket Pipelines** | GCP IAM Credentials | Workload Identity Pool (`BITBUCKET_STEP_OIDC_TOKEN` + `GCP_WORKLOAD_IDENTITY_PROVIDER`) | `bitbucket-pipelines.yml` enables `oidc: true` on all GCP steps and exchanges `BITBUCKET_STEP_OIDC_TOKEN` for short-lived credentials, with fallback to `GCP_SA_KEY` only when OIDC variables are unset. |

---

## 2. Kubernetes Pod-Level Workload Identity Across Both Production Dataplanes

- **AWS IRSA (IAM Roles for Service Accounts):**
  - Primary EKS dataplane (`module.eks`): `module.irsa_lb_controller` binds `kube-system:aws-load-balancer-controller` to `module.eks.oidc_provider_arn`.
  - Secondary Production EKS dataplane (`module.eks_dp2`): `module.irsa_lb_controller_dp2` binds `kube-system:aws-load-balancer-controller` to `module.eks_dp2[0].oidc_provider_arn`.
- **Azure Workload Identity & Managed Identity:**
  - Both `module.aks` and `module.aks_dp2` kubelet identities are granted `AcrPull` on Azure Container Registry (`azurerm_role_assignment.aks_acr` and `azurerm_role_assignment.aks_dp2_acr`) and `Key Vault Secrets User` on Azure Key Vault (`azurerm_role_assignment.aks_secrets_reader` and `azurerm_role_assignment.aks_dp2_secrets_reader`).
  - Both `module.workload_identity` and `module.workload_identity_dp2` federate `default:backend-workload-identity` against each cluster's OIDC issuer URL.
- **GCP Workload Identity:**
  - Both `module.gke` and `module.gke_dp2` share the project-wide GKE Workload Identity pool (`${var.project_id}.svc.id.goog`), bound via `module.workload_identity` to `default/backend-workload-identity`.

---

## 3. Dynamic Secrets & Encryption Management

1. **HashiCorp Vault Dynamic Database Credentials:**
   - Vault (`k8s/vault/`) issues short-lived (`1h` default TTL, `24h` max TTL) PostgreSQL roles for each microservice database (`products-db-role`, `orders-db-role`, `inventory-db-role`, `payments-db-role`, `fulfillment-db-role`, `analytics-db-role`) via Vault Agent Injector sidecars.
2. **Cloud KMS & CSI Secret Stores:**
   - Cloud KMS keys (`module.kms` in AWS and GCP; Azure Key Vault with RBAC authorization and soft-delete retention in Azure) encrypt storage buckets, managed databases, Redis caches, and Kafka brokers at rest.
   - `helm/microservices-umbrella/templates/secretproviderclass.yaml` provides opt-in Azure Key Vault CSI SecretProviderClass integration.
