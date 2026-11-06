# ADR-014: Argo CD 3.6.1 Modernization, Backstage IDP Adoption & Multi-Cloud DevSecOps Standardization

- **Status:** Accepted
- **Date:** 2026-11-06
- **Deciders:** Platform Architecture, DevSecOps & SRE Governance

## 1. Context and Problem Statement

A comprehensive repository-wide audit identified four strategic platform engineering gaps:
1. **Argo CD Version Drift & Configuration Gaps:** Argo CD versions drifted across `.env` (`3.5.5` / chart `10.10.3`), `helm/microservices-umbrella/values.yaml` (`3.5.6` / chart `10.11.1`), `terraform/environments/local-minikube/main.tf` (chart `10.11.6`), and `.github/workflows/_service-ci-cd-template.yml` (unpinned `latest` CLI). Furthermore, `local-minikube/main.tf` used an invalid Helm value key (`applicationController.resources.requests.memory` instead of `controller.resources.requests.memory`), and no production Helm values profile codified Argo CD 3.6 controller tuning, Keycloak OIDC SSO, granular `rollback` RBAC, or Prometheus `ServiceMonitor`s.
2. **Multi-Cloud DevSecOps Asymmetry:** Bitbucket Pipelines (`bitbucket-pipelines.yml`) lacked Semgrep SAST in its `&sast` step; GitHub Actions and Azure DevOps installed unpinned Semgrep without a centralized ruleset; Azure DevOps still referenced Node.js `22.x`; and Cosign only verified a static blob (`supply-chain-manifest.json`) without signing or verifying pushed OCI container images by immutable `@sha256` digest.
3. **Internal Developer Portal (IDP) Absence:** The platform lacked a Backstage catalog, Golden Path Scaffolder templates, and TechDocs configuration to standardize developer onboarding and service ownership.

## 2. Decision

1. **Standardize on Argo CD `v3.6.1` (`argo/argo-cd` Helm Chart `10.14.0`):**
   - Pin `ARGOCD_VERSION=3.6.1` and `ARGOCD_HELM_CHART_VERSION=10.14.0` across all configurations and CI workflows.
   - Maintain dedicated, schema-validated Helm values profiles in `helm/values/argocd-minikube.yaml` and `helm/values/argocd-prod.yaml`.
   - Enforce least-privilege RBAC (`policy.default: role:readonly`) including Argo CD 3.6's separate `applications, rollback` permission and Keycloak OIDC (`microservices-realm`) group bindings.
2. **Harmonize Multi-Cloud DevSecOps & OCI Image Signing:**
   - Pin Semgrep to `1.110.0` across GitHub Actions, Azure DevOps, and Bitbucket Pipelines with a centralized policy ruleset at `devsecops/sast/semgrep/semgrep-rules.yaml`.
   - Integrate Cosign `v3.1.3` OCI image signing by immutable `@sha256` digest upon registry push and pre-deployment signature verification before Argo CD or Helm promotion, while preserving `verify-blob` verification on `supply-chain-manifest.json`.
   - Standardize Azure DevOps on Node.js `24.x` (`versionSpec: '24.x'`).
3. **Adopt Backstage IDP (`v1.36.0`) with Strict Operational Independence:**
   - Model all Domains, Systems, 12 Components, 9 APIs, 6 Cloud Resources, and 5 Golden Path Scaffolder templates in `catalog-info.yaml` and `backstage/`.
   - Enforce operational independence: Backstage is strictly a read-only visibility and scaffolding portal and never sits in the runtime request path or blocks CI/CD, Terraform, Gatekeeper, or Argo CD operations.

## 3. Consequences

- **Positive:** Eliminates version drift across local and cloud GitOps control planes; closes SAST and OCI supply-chain verification gaps across AWS, Azure, and GCP pipelines; provides developers with governed Golden Path templates and unified catalog visibility.
- **Negative / Trade-offs:** Upgrading Argo CD CRDs in live clusters requires `kubectl apply --server-side --force-conflicts` due to CRD annotation size limits, documented in [`ARGOCD_3_6_UPGRADE_AND_ROLLBACK.md`](../../02-operations/ARGOCD_3_6_UPGRADE_AND_ROLLBACK.md).
