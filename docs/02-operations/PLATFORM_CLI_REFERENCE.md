# Platform CLI Reference

> [!TIP]
> [Enterprise Platform Hub](../../README.md) > **02. Operations** > Platform CLI

> [!NOTE]
> All platform PowerShell scripts (`*.ps1`) are standardized on **PowerShell 7+ (`pwsh`)** with `#Requires -Version 7.0` and cross-platform shebangs `#!/usr/bin/env pwsh`. Legacy Windows PowerShell 5.1 (`powershell.exe`) is intentionally blocked by `#Requires` to ensure deterministic UTF-8 encoding, modern parameter splatting, and complete cross-platform parity between Windows, macOS, Linux, and GitHub Actions runners.

The platform provides two independent, non-cascading PowerShell entrypoints:
- [`platform-minikube.ps1`](../../platform-minikube.ps1) for local zero-cloud-cost development, Istio, Gatekeeper, MLOps, and Vault.
- [`platform-multicloud.ps1`](../../platform-multicloud.ps1) for enterprise cloud operations across AWS, Azure, and GCP.
Each entrypoint is standalone and contains only the runtime helpers required for its platform: local Minikube operations or AWS, Azure, and GCP operations.

| Platform | Entrypoint | Infrastructure and cluster |
| --- | --- | --- |
| Local | [`platform-minikube.ps1`](../../platform-minikube.ps1) | Minikube, local images, Istio/Gatekeeper, MLOps, Vault, and local observability |
| Multi-Cloud (AWS, Azure, GCP) | [`platform-multicloud.ps1`](../../platform-multicloud.ps1) | Cloud-specific Terraform lifecycle; EKS/AKS/GKE delivery where a matching values profile exists; endpoint-based post-deploy checks |

## Usage

```powershell
# Local Minikube
.\platform-minikube.ps1 <command> [options]

# Multi-Cloud (AWS, Azure, GCP)
.\platform-multicloud.ps1 <command> -Provider <aws|azure|gcp> -Environment <dev|staging|prod> [options]
```

Run an entrypoint with `help` for its available commands. A provider entrypoint
rejects commands outside its declared `ValidateSet`; cloud entrypoints do not
accept local build, test, cost-estimation, or Minikube operations. Cloud entrypoints
provide `security-scan` for local Gitleaks, TFLint, and Trivy checks against the
selected provider's Terraform root and shared Helm chart; this complements, but
does not replace, the provider's CI security gates.

## Minikube

```powershell
# Full initial platform bootstrap (Terraform, Gatekeeper, Helm, Keycloak realm bootstrap)
.\platform-minikube.ps1 up
.\platform-minikube.ps1 up -WithoutIstio                  # Lightweight native K8s mode

# Fast platform resume (< 30s) bypassing Terraform, Gatekeeper, Helm build, and FinOps
.\platform-minikube.ps1 start                            # Resumes cluster, pods & tunnels
.\platform-minikube.ps1 start -WithoutIstio              # Fast resume in lightweight mode
.\platform-minikube.ps1 start -DeployCanary -CanaryImageTag v2.1 # Fast resume with canary
.\platform-minikube.ps1 up -Fast                         # Equivalent to start

# Workload and DevSecOps commands
.\platform-minikube.ps1 build                            # Compile container images from source and reload into Minikube
.\platform-minikube.ps1 build -Service orders-service    # Fast targeted rebuild & reload of a single service
.\platform-minikube.ps1 build -IncludeMlops              # Include MLOps images (forecast, training, mlflow)
.\platform-minikube.ps1 build -IncludeMlops -Push        # Compile and push to Docker Hub with retry backoff
.\platform-minikube.ps1 build -PushOnly -ImageTag 1.0.0  # Push existing local images without rebuilding
.\platform-minikube.ps1 test                             # Run Java 21 + Maven reactor unit tests
.\platform-minikube.ps1 security-scan                    # Run 5 Shift-Left gates (Gitleaks, TFLint, Trivy, Conftest, Cosign)
.\platform-minikube.ps1 dast                             # Run OWASP ZAP baseline dynamic application security scan against live frontend
.\platform-minikube.ps1 contract                         # Run Newman API contract tests (23/23 passing)
.\platform-minikube.ps1 performance                      # Run k6 load and latency SLO benchmark
.\platform-minikube.ps1 bcdr                             # Run BCDR backup & disaster recovery simulation drill
.\platform-minikube.ps1 set-tag -ImageTag 1.2.0          # Synchronize container image tags in values-minikube.yaml
.\platform-minikube.ps1 set-tag -ImageTag 1.2.0 -Service orders-service # Synchronize a single service only
.\platform-minikube.ps1 set-tag -ImageTag 1.2.0 -TargetEnv all          # Synchronize tags across all Helm values environments
.\platform-minikube.ps1 vault -VaultAction status        # Hybrid host Vault CLI + K8s fallback (init|seed|rotate|status)
.\platform-minikube.ps1 mlops                            # Deploy/refresh MLflow & MLOps
.\platform-minikube.ps1 canary -Action rollout -Namespace dev
.\platform-minikube.ps1 doctor                           # Deep cluster health diagnostics
.\platform-minikube.ps1 urls                             # Active local tunnels & credentials

# Teardown and pause
.\platform-minikube.ps1 down                             # Safe pause (preserves DB/cluster state)
.\platform-minikube.ps1 down -Destroy                    # Complete purge of VM, volumes & state
```

For recommended host capacity and Minikube defaults, see the canonical
[local resource profile](./LOCAL_DEPLOYMENT.md#-prerequisites).
`-WithoutIstio` selects the smaller no-mesh profile.
`-Fast` (or `start`/`resume`) bypasses redundant infrastructure re-runs, bringing existing
workloads and tunnels back online in under 30 seconds.

`mlops` deploys the local MLflow tracking service, Kafka-to-Parquet capture,
forecast API, and scheduled model-training workload. It expects the Minikube
base platform to be present.

`set-tag` synchronizes container image tags across Helm values manifests (`helm/values/values-*.yaml`) using `yq`. It protects third-party components (such as Cosmo Router, Kiali, and Prometheus) from accidental mutation while updating application microservices (`georgegxx/*`, frontend, and MLOps). Supports targeting a single service (`-Service <name>`) or all environment profiles (`-TargetEnv all`), producing an immediate Git diff summary.

## Cloud lifecycle

Each cloud entrypoint performs provider-specific preflight before cloud actions:

| Provider | Authentication check | Cluster setup | Host CLI inventory |
| --- | --- | --- | --- |
| AWS EKS | `aws sts get-caller-identity` | Select the intended EKS context before Kubernetes operations | `terraform`, `aws`, `kubectl`, `helm`, `gitleaks`, `tflint`, `trivy`, `conftest` |
| AWS ECS Fargate / EC2 Compact | `aws sts get-caller-identity` | Not applicable; this CLI provides Terraform infrastructure lifecycle only | `terraform`, `aws`, `gitleaks`, `tflint`, `trivy` |
| Azure AKS | `az account show` | Select the intended AKS context before Kubernetes operations | `terraform`, `az`, `kubectl`, `helm`, `gitleaks`, `tflint`, `trivy`, `conftest` |
| GCP GKE | Active `gcloud` account and configured project | Select the intended GKE context before Kubernetes operations | `terraform`, `gcloud`, `kubectl`, `helm`, `gitleaks`, `tflint`, `trivy`, `conftest` |

Plan/apply/destroy operations require a configured durable remote backend.
Azure and GCP additionally require their local backend configuration file.
Kubernetes commands use the current `kubectl` context; select and verify the
intended provider cluster before running delivery, Gatekeeper, or diagnostics.
The CLI does not rewrite kubeconfig or switch cloud identities. No command
silently falls back to local Terraform state. `plan` and `apply` can create a missing environment workspace;
`status`, `doctor`, `destroy`, and `unlock` require that workspace to already exist.
Production provisions two data-plane clusters. `doctor`, `verify`, and `status`
accept `-DataPlane all|primary|secondary` (default `all`) to choose diagnostic
targets; the secondary data plane exists only for `prod`. Production Terraform
`plan`, `apply`, and `destroy` require an explicit `-DataPlane` selection.
`primary` and `secondary` pass Terraform targets for that cluster module only;
`all` uses the complete root and includes shared infrastructure. This scopes
operations without changing the current shared Terraform state; it is not yet
independent state ownership. Avoid `all` for destruction unless the intent is
to remove the complete environment.
Cloud resource sizing is defined by each provider's Terraform configuration
and environment variables, not by the Minikube CPU, memory, or disk options.

```powershell
.\platform-multicloud.ps1 plan -Provider aws -Environment staging
.\platform-multicloud.ps1 apply -Provider aws -Environment staging
.\platform-multicloud.ps1 apply -Provider aws -Environment prod -DataPlane primary
.\platform-multicloud.ps1 destroy -Provider aws -Environment prod -DataPlane secondary
.\platform-multicloud.ps1 doctor -Provider azure
.\platform-multicloud.ps1 status -Provider gcp -Environment prod
.\platform-multicloud.ps1 status -Provider aws -Environment prod -DataPlane secondary
```

`destroy` is destructive and prompts for confirmation unless `-AutoApprove` is
explicitly provided. Review the plan and target environment before approving.
For a single production cluster, specify `-DataPlane primary` or
`-DataPlane secondary`; these selections limit Terraform to the chosen cluster
module (and its declared dependencies), rather than destroying the shared root.
`-DataPlane all` is an explicit full-environment operation and can remove shared
resources as well as both clusters.

`apply` provisions cloud infrastructure only: it does not build/push application
images or install application charts. Application delivery is provider-specific:

- GitHub Actions provides AWS CI and Argo CD provides AWS CD.
  `sync-argocd` is AWS-only and requests reconciliation of the already-installed
  Application; it does not apply local manifests.
- Azure application pipelines live in
  [`azure-devops/pipelines/`](../../azure-devops/pipelines/) and use the shared
  [`app-stages.yml`](../../azure-devops/templates/app-stages.yml) and
  [`helm-deploy.yml`](../../azure-devops/templates/steps/helm-deploy.yml) templates
  to build/publish images and deploy the released Helm chart directly to AKS (`apply-workloads`).
  Those pipeline stages also own application rollback (`rollback`).
- Bitbucket Pipelines deploys application releases directly to GKE with Helm and
  owns GCP deployment/rollback (`apply-workloads`, `rollback`).

`platform-multicloud.ps1` exposes a unified, non-cascading operational surface with its cloud-specific DevSecOps, Terraform, delivery, and post-deploy helpers defined in the same script:

- `pre-deploy`: Shift-Left static security gate running Gitleaks secret detection, TFLint, Trivy IaC misconfiguration, Conftest (OPA) Rego policy validation, optional Cosign container image signature verification, and optional Graphviz architecture modeling (`-GenerateGraph`).
- `plan`: Formats, validates, and generates a verified binary plan artifact (`.tfplan`) with support for `-Flavor` (AWS: `eks`, `ecs-fargate`, `ec2-compact`), `-Target`, `-Replace`, `-Var`, and `-VarFile`.
- `apply`: Applies the verified binary plan artifact with production safeguards (explicit confirmation prompt showing active account/project before apply).
- `destroy`: Safely removes cloud resources with interactive confirmation.
- `drift`: Audits live infrastructure drift against remote state via `terraform plan -detailed-exitcode -refresh-only`.
- `output`: Displays and exports Terraform state outputs.
- `unlock`: Forcibly releases a verified stale Terraform state lock (`-LockId <id>`).
- `post-deploy`: Live dynamic quality and DAST gate executed against the deployed endpoint (`-TargetUrl <url>`), with `-KeycloakUrl <url>` (or `KEYCLOAK_URL`) for authenticated Newman checks. It runs Smoke tests (`smoke.py`), Newman API contract integration tests (`microservices.postman_collection.json`), Grafana k6 1.8.1 SLA benchmarks (`load-test.js`), and OWASP ZAP baseline DAST using the shared `rules.tsv` alert rules.
- `pipeline`: Executes the full end-to-end delivery pipeline (`pre-deploy` -> `apply` -> delivery sync -> `post-deploy`).
- AWS `pipeline`, ArgoCD, Gatekeeper, and Kubernetes diagnostics support EKS only. AWS ECS Fargate and EC2 Compact remain available for Terraform infrastructure lifecycle commands; this CLI has no workload delivery driver for those flavors.
- Helm policy rendering and workload deployment select `values-eks-<environment>.yaml`, `values-aks-<environment>.yaml`, or `values-gke-<environment>.yaml`. Missing provider/environment profiles fail explicitly; the cloud CLI never substitutes Minikube values. Current AKS profiles are `dev` and `prod`; current GKE profile is `dev` only. Add the missing provider/environment values files before using AKS staging or GKE staging/prod workload delivery.
- `sync-argocd`: (AWS only) Triggers Argo CD GitOps reconciliation for microservices on EKS.
- `apply-workloads`: (Azure & GCP) Deploys the microservices Umbrella Helm chart directly to AKS/GKE.
- `rollback`: (Azure & GCP) Executes immediate Helm atomic rollback (`-Revision <int>`) on AKS/GKE.
- `gatekeeper`: Manages OPA Gatekeeper in the target cluster: deploys `ConstraintTemplates` and `Constraints` from `devsecops/policies/gatekeeper/`, audits runtime compliance across workloads, tests admission webhook rejection, or installs the Gatekeeper Helm chart (`-Action audit|deploy|test|install`).
- `doctor` and `status`: Audits cloud credentials, Kubernetes connectivity, nodes, active Gatekeeper constraints, and workload violations.
- `tools`: Audits host CLI dependencies across pre-deploy, IaC, and post-deploy runners (`-Install` attempts installation via WinGet).

```powershell
# AWS Examples
.\platform-multicloud.ps1 pre-deploy -Provider aws -Environment dev
.\platform-multicloud.ps1 plan -Provider aws -Environment staging -Flavor eks
.\platform-multicloud.ps1 apply -Provider aws -Environment staging -PlanFile .terraform/tfplan-staging.binary
.\platform-multicloud.ps1 sync-argocd -Provider aws -Environment staging
.\platform-multicloud.ps1 post-deploy -Provider aws -Environment staging -TargetUrl "https://staging.domain.com" -KeycloakUrl "https://auth.staging.domain.com"
.\platform-multicloud.ps1 drift -Provider aws -Environment prod

# Azure & GCP Examples
.\platform-multicloud.ps1 apply-workloads -Provider azure -Environment dev
.\platform-multicloud.ps1 rollback -Provider azure -Environment dev -Revision 2
.\platform-multicloud.ps1 pipeline -Provider gcp -Environment dev -TargetUrl "https://gcp-dev.domain.com" -KeycloakUrl "https://auth.gcp-dev.domain.com"
```

The current Terraform backend stores the production root in a single state. Per-data-plane commands are deliberately module-targeted as an operational safety boundary; the CI pipeline must use the same target selection.

The Minikube entrypoint owns local developer tooling, image builds, local Vault, and Minikube capabilities. Its `tools -Install` audits/installs the larger local inventory; a cloud `tools -Install` audits and installs the cloud-native DevSecOps and provider toolchain.

## Terraform working data

Terraform commands are serialized per working directory. Terraform `init` uses
`-upgrade` and retries transient Windows provider-file locks. Review and commit
intended provider lock-file updates; other Terraform failures are surfaced
without retrying. Cloud backend, identity, and context operations remain
provider-owned; the common library supplies shared command runtime, process,
and validation helpers. Minikube's `down -Destroy` waits for the Terraform
working-directory lock, removes cached modules and local state after the
cluster is deleted, and preserves downloaded provider binaries under
`.terraform/providers`. Editors such as VS Code's Terraform language server may
keep those executables open; retaining the provider cache avoids a Windows file
lock and does not prevent a later `terraform init` from refreshing it.
