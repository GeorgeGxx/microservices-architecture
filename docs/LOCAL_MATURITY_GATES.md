# Local maturity gates for reliability, security and delivery

These checks let the project exercise production practices on a developer
machine without provisioning cloud resources. Terraform commands in CI use
`-backend=false`; no workflow in this file runs `terraform apply`.

## 1. Resilience and bounded load

The k6 scenario `scripts/testing/resilience-smoke.js` drives the storefront's
`/graphql` endpoint through Nginx and Cosmo Router with only two virtual users
for 30 seconds. It enforces a 2-second p95 and fewer than 2% failed requests.
This is a repeatable smoke baseline, not a capacity benchmark or DDoS test.

```powershell
k6 run scripts/testing/resilience-smoke.js
$env:BASE_URL = 'http://127.0.0.1:5173'
k6 run scripts/testing/resilience-smoke.js
```

Run it only against a stack you own. Increase VUs and duration separately when
you intentionally perform a load test.

## 2. Observability and traceability

The local quality workflow parses every Grafana dashboard JSON file and checks
the Prometheus configuration and recording/alert rules with `promtool`. Runtime
verification remains available in the dashboards and data sources for
Prometheus, Loki, Tempo and Alloy; a green config check does not claim that the
containers are running or that a trace was emitted.

For runtime correlation, use the same smoke request while watching Grafana and
verify the frontend request, Cosmo Router span, service metrics, and logs.

## 3. Backup and restore drill

`scripts/testing/backup-restore-check.ps1` creates a plain SQL backup of the
Compose `db-orders` database, restores it into a uniquely named temporary
database in the same container, compares user-table counts, drops only that
temporary database, and retains the backup under `backups/local-drills/`.
It does not overwrite or drop the source database.

```powershell
.\scripts\testing\backup-restore-check.ps1
# Override names when your Compose database uses different values:
.\scripts\testing\backup-restore-check.ps1 -DatabaseName ms_orders -DatabaseUser postgres
```

The container must be running and the selected database must exist. Verify the
retained backup policy and protect/remove the local backup file according to
your data-handling rules.

## 4. Security and audit controls

The GitHub local quality workflow runs Checkov against Terraform. Its findings
remain advisory while the existing cloud infrastructure is being calibrated;
promote it to a blocking gate after reviewing and documenting accepted legacy
findings. Keep credentials in the CI secret store, never in Terraform variables
files or state artifacts. Changes that alter authorization, secret delivery,
image provenance, or edge policies should include a negative security test.

The managed cloud database modules apply `prevent_destroy` and provider deletion
protection where supported. Because Terraform requires a literal lifecycle
setting, protection is active for every environment that enables these managed
database modules (cloud staging/prod); Terraform destroy then requires an
intentional code change to remove that guard. Resource preconditions reject
unsafe production settings, and postconditions verify backup/encryption
properties after creation or update. Minikube and in-cluster dev databases
remain recreatable. Existing `create_before_destroy` and `ignore_changes` usages
remain limited to resources where replacement or an external autoscaler makes
sense.

For a provider-free exercise of all six lifecycle controls, use
`terraform/examples/lifecycle`. It contains only Terraform's built-in
`terraform_data` resources and does not provision cloud infrastructure. The
protected sample intentionally prevents destroy; use a disposable local state
and remove that guard in the example only when practicing teardown. The rollout
sample demonstrates `replace_triggered_by`, preconditions, postconditions, and
create-before-destroy independently of that destroy guard.

## 5. Quality gates and release flow

`.github/workflows/local-quality-gates.yml` checks Terraform formatting and
validates all four environment roots (`local-minikube`, AWS, Azure, GCP) plus
the provider-free lifecycle example with remote
backends disabled. It also checks Compose interpolation using `.example.env`,
Python test-tool syntax, Prometheus config/rules, and Grafana dashboard JSON.
The workflow does not start the full platform stack, publish images, sync
ArgoCD, or apply infrastructure.

Run the equivalent quick local checks before opening a PR:

```powershell
terraform fmt -check -recursive terraform
docker compose config --quiet
python -m compileall -q scripts/testing
```

For cloud, preserve the plan/apply boundary: review a saved plan, use a protected
environment approval for production, apply only the reviewed plan, and never
recover from a missing plan by creating a fresh `-auto-approve` apply. The local
Minikube workflow remains separate from cloud credentials and state.

The AWS infrastructure workflow runs cloud planning only when manually
dispatched; it no longer applies automatically from a branch push. Its apply
jobs require the saved plan from that run and the `DB_MASTER_PASSWORD` secret.
Configure required reviewers on the GitHub environments `staging-infra` and
`prod-infra` in repository settings, especially for production. The one-day
plan artifact can contain sensitive values, so keep workflow access restricted.
