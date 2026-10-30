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

## 3. Recommended Branch Protection Policies

Configure the following branch protection rules in GitHub, Azure Repos, and Bitbucket:

| Policy Control | `develop` | `staging` | `master` |
|---|---|---|---|
| **Require Pull Request before merging** | Yes (1+ reviewer) | Yes (1+ reviewer) | Yes (2+ reviewers, CODEOWNERS) |
| **Require status checks to pass** | Unit tests, Gitleaks, Semgrep, Trivy, Conftest, `terraform validate` | All `develop` checks + Newman, E2E, k6, OWASP ZAP | All `staging` checks + Release Readiness Verification |
| **Require signed commits** | Recommended | Recommended | Mandatory |
| **Block force pushes & branch deletion** | Yes | Yes | Yes |
| **Environment deployment approvals** | Automatic | Automatic or QA Lead | Mandatory Manual Approval (`production` environment) |
