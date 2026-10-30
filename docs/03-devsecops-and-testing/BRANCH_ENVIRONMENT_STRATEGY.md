# Git Branch & Multi-Environment Promotion Strategy

## 1. Mandatory Branch-to-Environment Mapping

The repository enforces a strict three-branch promotion model across **Azure DevOps**, **Bitbucket Pipelines**, and **GitHub Actions + Argo CD**:

| Git Branch | Target Environment | Topology | Purpose |
|---|---|---|---|
| `develop` | **DEV** | 1 Dataplane | Continuous integration, unit/coverage tests, SAST/secrets/IaC scans, container build + CycloneDX SBOM, and automated DEV deployment. |
| `staging` | **STAGING / QA** | 1 Dataplane | Promotion/validation of candidate artifacts, Newman API contract tests, storefront synthetic E2E checks, k6 performance SLO gates, and OWASP ZAP DAST baseline. |
| `master` | **PRODUCTION** | **2 Independent Dataplanes (DP1 + DP2)** | Controlled production release of staging-verified immutable digests (`@sha256:...`), manual approval gates, destructive-plan guards, and dual-dataplane rollout verification. |

The canonical promotion path is:

```text
develop  ──(PR + CI/Security Gates)──►  staging  ──(PR + QA/DAST/k6 Gates + Approval)──►  master
```

---

## 2. Immutable Artifact Promotion Rules

1. **Build Once, Promote by Digest (`@sha256`):**
   - Every container image is built with BuildKit/Buildx, scanned by Trivy (`CRITICAL`/`HIGH`), and accompanied by a CycloneDX SBOM (`*.cdx.json`).
   - During `staging` and `master` promotions across Azure ACR (`azure-devops/templates/app-stages.yml`), Google Artifact Registry (`bitbucket-pipelines.yml`), and Docker Hub / AWS ECR (`.github/workflows/_service-ci-cd-template.yml`), the pipeline checks whether the immutable commit SHA artifact already exists in the registry and promotes the exact `@sha256:...` digest without overwriting or rebuilding.
2. **Helm Umbrella Chart Immutability:**
   - The umbrella chart (`helm/microservices-umbrella/Chart.yaml`) is version-pinned (`1.0.0`) and verified against `oci://ghcr.io/georgegxx/helm-charts/microservices-umbrella` via `.github/workflows/helm-chart-release.yml` from `master`.

---

## 3. Enforced GitHub Governance & Branch Protection Policies

The repository enforces the following live governance rules across GitHub Environments, Branch Protection, and PR lifecycle settings (aligned across Azure Repos and Bitbucket):

### 3.1 GitHub Environments (`Settings` $\rightarrow$ `Environments`)

| GitHub Environment | Allowed Deployment Branch Policy | Required Reviewers (Manual Approval) | Purpose |
|---|---|---|---|
| `dev` | `develop` (custom branch policy) | None (automated continuous delivery) | Local Minikube / Dev environment synchronization (`microservices-dev`). |
| `staging` | `staging` (custom branch policy) | None (automated upon PR merge to `staging`) | Pre-production QA/Staging validation (`microservices-staging`). |
| `production` | `master` (custom branch policy) | Mandatory Reviewer (`GeorgeGxx`) | Blocks `gitops-argocd-sync` and `tf-apply-prod` until manually approved. |

### 3.2 Branch Protection & Repository Rules

| Policy Control | `develop` | `staging` | `master` |
|---|---|---|---|
| **Require Pull Request before merging** | Optional (direct push allowed for rapid dev iteration) | Mandatory (1+ approval, dismiss stale reviews, conversation resolution) | Mandatory (1+ approval, dismiss stale reviews, conversation resolution) |
| **Block force pushes (`allow_force_pushes: false`)** | Enforced | Enforced | Enforced |
| **Block branch deletion (`allow_deletions: false`)** | Enforced | Enforced | Enforced |
| **Admin bypass (`enforce_admins: false`)** | Enabled for repository owner solo operations (`--admin`) | Enabled for repository owner solo operations (`--admin`) | Enabled for repository owner solo operations (`--admin`) |
| **Auto-delete head branches (`delete_branch_on_merge`)** | Enabled repository-wide (automatically cleans up merged feature and Dependabot branches) | Enabled repository-wide | Enabled repository-wide |

---

## 4. Paused Multi-Cloud Deployment Posture (`staging` & `master`) & Reactivation Checklist

To prevent unnecessary CI/CD runner consumption and failed cloud authentication attempts while cloud clusters (AWS EKS, Azure AKS, GCP GKE) are not actively provisioned, **`staging` and `master` cloud deployments are paused by default** while keeping **`develop`** fully active for local/dev workflows:

| Platform | Paused Configuration (`staging` & `master`) | Reactivation Procedure (When Ready for Cloud Deployment) |
|---|---|---|
| **GitHub Actions (AWS)** | • `.github/workflows/service-*.yml`, `local-quality-gates.yml`, and `security-scan.yml` trigger only on `branches: [develop]`.<br>• In `.github/workflows/_service-ci-cd-template.yml`, `push-dockerhub` and `gitops-argocd-sync` on `staging` and `master` require repository variable `vars.ENABLE_CLOUD_DEPLOY == 'true'`.<br>• `.github/workflows/terraform-aws.yml` runs on manual `workflow_dispatch`. | 1. Uncomment/restore `branches: [develop, staging, master]` in `.github/workflows/*.yml`.<br>2. Set repository variable `ENABLE_CLOUD_DEPLOY=true` (`gh variable set ENABLE_CLOUD_DEPLOY --body "true"`). |
| **Argo CD (GitOps)** | • `automated` sync is commented out in `argocd/application-staging.yaml` and disabled in `argocd/application-prod.yaml` (`DP1`) and `argocd/application-prod-dp2.yaml` (`DP2`).<br>• Only `argocd/application-dev.yaml` (`develop`) retains `automated: { prune: true, selfHeal: true }`. | 1. Uncomment `automated` in `argocd/application-staging.yaml` for continuous EKS Staging delivery.<br>2. Keep `application-prod.yaml` and `application-prod-dp2.yaml` without `automated` so production syncs only when triggered by the approved `gitops-argocd-sync` job. |
| **Azure DevOps (AKS)** | • `azure-devops/pipelines/*.yml` trigger only on `include: [develop]`.<br>• `azure-devops/templates/app-stages.yml` sets `enableCloudStagingProdDeploy: false` by default.<br>• `azure-devops/pipelines/infra.yml` sets `enableCloudPlanApply: false` by default. | 1. Restore `include: [develop, staging, master]` in `azure-devops/pipelines/*.yml`.<br>2. Set `enableCloudStagingProdDeploy: true` in `azure-devops/templates/app-stages.yml` (and `enableCloudPlanApply: true` in `infra.yml`). |
| **Bitbucket Pipelines (GCP)** | • `branches.staging` and `branches.master` blocks in `bitbucket-pipelines.yml` are commented out; only `branches.develop` is active. | Uncomment the `staging:` and `master:` branch pipeline blocks in `bitbucket-pipelines.yml`. |

---

## 5. Promotion & Manual Approval Runbook (`develop` $\rightarrow$ `staging` $\rightarrow$ `master`)

### Step 1: Promote `develop` $\rightarrow$ `staging` via Pull Request

```bash
# 1. Create the promotion Pull Request from develop into staging
gh pr create --base staging --head develop \
  --title "chore(release): promote develop to staging" \
  --body "Promote validated changes from develop into staging"

# 2. Merge the Pull Request into staging (do NOT pass --delete-branch on permanent branches)
gh pr merge --merge --admin
```

### Step 2: Promote `staging` $\rightarrow$ `master` via Pull Request

```bash
# 1. Create the release Pull Request from staging into master
gh pr create --base master --head staging \
  --title "chore(release): promote staging to master" \
  --body "Promote staging-verified release candidate into master (production)"

# 2. Merge the Pull Request into master
gh pr merge --merge --admin
```

### Step 3: Approve the Production Deployment Gate (When Cloud Deployment is Enabled)

When `ENABLE_CLOUD_DEPLOY=true` and `master` workflows are active:
1. Merging into `master` runs CI/security checks and pauses at job **`7. ArgoCD GitOps Sync`** in **Waiting (Pending review)** state due to the `production` GitHub Environment gate.
2. Approve the deployment either via the GitHub UI (**Actions** $\rightarrow$ select workflow run $\rightarrow$ **Review deployments** $\rightarrow$ check **`production`** $\rightarrow$ **Approve and deploy**) or via `gh` CLI:

```bash
# List recent workflow runs on master waiting for approval
gh run list --branch master --limit 5

# Approve the pending production environment deployment (production environment ID: 25225601755)
gh api -X POST repos/GeorgeGxx/microservices-architecture/actions/runs/<RUN_ID>/pending_deployments \
  -F "environment_ids[]=25225601755" \
  -f state=approved \
  -f comment="Approved for production dual-dataplane rollout (DP1 + DP2)"
```
