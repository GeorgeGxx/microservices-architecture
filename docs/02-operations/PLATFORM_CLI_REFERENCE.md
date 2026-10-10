# Platform CLI Reference

> [!TIP]
> [Enterprise Platform Hub](../../README.md) > **02. Operations** > Platform CLI

The platform provides two independent, non-cascading PowerShell entrypoints:
- [`platform-minikube.ps1`](../../platform-minikube.ps1) for local zero-cloud-cost development, Istio, Gatekeeper, MLOps, and Vault.
- [`platform-multicloud.ps1`](../../platform-multicloud.ps1) for enterprise cloud operations across AWS, Azure, and GCP.
Shared implementation helpers and the unified DevSecOps core engine live in [`platform-common.ps1`](../../platform-common.ps1).

| Platform | Entrypoint | Infrastructure and cluster |
| --- | --- | --- |
| Local | [`platform-minikube.ps1`](../../platform-minikube.ps1) | Minikube, local images, Istio/Gatekeeper, MLOps, Vault, and local observability |
| Multi-Cloud (AWS, Azure, GCP) | [`platform-multicloud.ps1`](../../platform-multicloud.ps1) | AWS (EKS/ECS/EC2), Azure (AKS), GCP (GKE), durable remote state, Delivery, and Post-Deploy Gates |

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
.\platform-minikube.ps1 up
.\platform-minikube.ps1 mlops
.\platform-minikube.ps1 canary -Action rollout -Namespace dev
.\platform-minikube.ps1 doctor
.\platform-minikube.ps1 down
```

For recommended host capacity and Minikube defaults, see the canonical
[local resource profile](./LOCAL_DEPLOYMENT.md#-prerequisites).
`-WithoutIstio` selects the smaller no-mesh profile.

`mlops` deploys the local MLflow tracking service, Kafka-to-Parquet capture,
forecast API, and scheduled model-training workload. It expects the Minikube
base platform to be present.

## Cloud lifecycle

Each cloud entrypoint performs provider-specific preflight before cloud actions:

| Provider | Authentication check | Cluster setup | Host CLI inventory |
| --- | --- | --- | --- |
| AWS | `aws sts get-caller-identity` | `aws eks update-kubeconfig` | `terraform`, `aws`, `kubectl`, `gitleaks`, `tflint`, `trivy` |
| Azure | `az account show` | `az aks get-credentials` | `terraform`, `az`, `kubectl`, `gitleaks`, `tflint`, `trivy` |
| GCP | Active `gcloud` account and configured project | `gcloud container clusters get-credentials` | `terraform`, `gcloud`, `kubectl`, `gitleaks`, `tflint`, `trivy` |

Plan/apply/destroy operations require a configured durable remote backend.
Azure and GCP additionally require their local backend configuration file.
Cloud diagnostics connect to the selected cluster(s) and restore the Kubernetes
context that was active before the command. No command silently falls back to
local state. `plan` and `apply` can create a missing environment workspace;
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

`platform-multicloud.ps1` exposes a unified, non-cascading operational surface powered directly by [`platform-common.ps1`](../../platform-common.ps1):

- `pre-deploy`: Shift-Left static security gate running Gitleaks secret detection, TFLint, Trivy IaC misconfiguration, Conftest (OPA) Rego policy validation, optional Cosign container image signature verification, and optional Graphviz architecture modeling (`-GenerateGraph`).
- `plan`: Formats, validates, and generates a verified binary plan artifact (`.tfplan`) with support for `-Flavor` (AWS: `eks`, `ecs-fargate`, `ec2-compact`), `-Target`, `-Replace`, `-Var`, and `-VarFile`.
- `apply`: Applies the verified binary plan artifact with production safeguards (explicit confirmation prompt showing active account/project before apply).
- `destroy`: Safely removes cloud resources with interactive confirmation.
- `drift`: Audits live infrastructure drift against remote state via `terraform plan -detailed-exitcode -refresh-only`.
- `output`: Displays and exports Terraform state outputs.
- `unlock`: Forcibly releases a verified stale Terraform state lock (`-LockId <id>`).
- `post-deploy`: Live dynamic quality and DAST gate executed strictly against the live deployed endpoint (`-TargetUrl <url>`), running Smoke tests (`smoke.py`), Newman API contract integration tests (`microservices.postman_collection.json`), Grafana k6 SLA benchmarks (`load-test.js`), and OWASP ZAP baseline DAST scans (`zap.yaml`).
- `pipeline`: Executes the full end-to-end delivery pipeline (`pre-deploy` -> `apply` -> delivery sync -> `post-deploy`).
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
.\platform-multicloud.ps1 post-deploy -Provider aws -Environment staging -TargetUrl "https://staging.domain.com"
.\platform-multicloud.ps1 drift -Provider aws -Environment prod

# Azure & GCP Examples
.\platform-multicloud.ps1 apply-workloads -Provider azure -Environment dev
.\platform-multicloud.ps1 rollback -Provider azure -Environment dev -Revision 2
.\platform-multicloud.ps1 pipeline -Provider gcp -Environment staging -TargetUrl "https://gcp-staging.domain.com"
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
