# 📦 Immutable Production Helm Chart Releases & Canary Rollouts

> [!TIP]
> 🧭 **[Enterprise Platform Hub](../../README.md)** > **02. Operations** > `HELM_AND_CANARY.md`

The production chart is released as a versioned OCI artifact in GitHub Container Registry (GHCR), independent of image releases:

```text
oci://ghcr.io/georgegxx/helm-charts/microservices-umbrella:<Chart.yaml version>
```

---

## Release procedure

1. Use the current `version` in `helm/microservices-umbrella/Chart.yaml` for the first publication if it has never been released. For every later chart-content change, increment it using stable SemVer (`MAJOR.MINOR.PATCH`); never reuse a released version.
2. If Federation composition inputs changed, run `platform-minikube.ps1 compose-router` and commit the generated router config with the source change.
3. Merge the chart change to `main`.
4. Create and push the matching release tag. For the first release at the current `1.0.0` version:

   ```powershell
   git tag helm-v1.0.0
   git push origin helm-v1.0.0
   ```

   Future releases use the matching bumped version, such as `helm-v1.0.1`.

The `.github/workflows/helm-chart-release.yml` workflow builds dependencies from the committed `Chart.lock`, validates and renders production values, packages the umbrella chart, then publishes it to GHCR. A manual run is also available from `main` with the exact version from `Chart.yaml`.

The `production` GitHub Environment should require an authorized reviewer. The workflow uses the repository-scoped `GITHUB_TOKEN` with `packages: write`; no long-lived registry password is needed for publishing. GHCR packages are private by default. For Argo CD to pull a private package, configure read-only GHCR credentials in each Argo CD installation; never commit that credential. A public chart package can instead be made public in GitHub package settings if its contents are suitable for public access.

Azure DevOps and Bitbucket are consumers, never publishers. Configure protected `GHCR_USERNAME` and `GHCR_TOKEN` variables in each deployment environment; the token needs read-only `read:packages` access to this package. Do not reuse the publishing token. Both pipelines read the desired chart version from the checked-out umbrella `Chart.yaml`, authenticate to GHCR, and deploy `oci://ghcr.io/georgegxx/helm-charts/microservices-umbrella` with that exact `--version`. The version must already have been released by GitHub Actions, or deployment fails before changing the Helm release.

The AWS, Azure, and GCP Terraform roots read the same `Chart.yaml` and expose `microservices_chart_repository`, `microservices_chart_version`, and `microservices_chart_reference` outputs for downstream release tooling. Terraform remains the owner of infrastructure; it does not create a second Helm release alongside Argo CD or the deployment pipelines. Each cloud root exposes these outputs in its `dev`, `staging`, and `prod` workspaces.

## Immutability checks

- The release tag must point to a commit reachable from `main`, and its version must match `Chart.yaml` exactly.
- Re-publishing the same version and identical package bytes is an idempotent no-op.
- If that version already exists with different bytes, publication fails. Increment the chart version instead of overwriting it.
- The workflow downloads the published artifact and compares its SHA-256 with the package built from the release commit.

Current Argo CD Applications still source the umbrella chart from Git branches. Publishing to GHCR does not silently change their source; migrating a production Application to OCI requires configuring GHCR read access and pinning `targetRevision` to the released version. This keeps current deployments safe until that migration is explicitly configured and validated.
