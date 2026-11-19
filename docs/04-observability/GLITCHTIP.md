# GlitchTip error tracking

## Selected release

- GlitchTip image: `glitchtip/glitchtip:7.0.0` (exact stable tag; latest stable observed on 2026-11-18).
- Official Helm chart: `9.2.0`, appVersion `7.0.0` (chart digest `sha256:a14b1face40ee3631ae017d5ed213ee19536f94e5d568cf06675eb9e8b8bf8f5`).
- Local database: PostgreSQL `18.7` (`postgres:18.7-alpine`); GlitchTip 7.0 requires PostgreSQL 15 or newer. The official installation page still says 14+, so the 7.0 release note takes precedence.
- The official chart's Valkey integration is enabled with authentication for Kubernetes. The local Compose instance uses PostgreSQL-only mode to keep the optional service count down.

## Local Compose

This is a separate, opt-in service set and has its own persistent PostgreSQL volume. It binds only to loopback on port 8090. Use synthetic data.

The PostgreSQL 18 image mounts its data volume at `/var/lib/postgresql`. This configuration is for a new PostgreSQL 18 data directory; it does not migrate an existing PostgreSQL 16 volume. Back up and migrate existing data with `pg_dump`/restore before switching.

```powershell
$env:GLITCHTIP_DB_PASSWORD = '<URL-safe local password>'
$env:GLITCHTIP_SECRET_KEY = '<generated random secret>'
docker compose -f compose.yaml -f compose.glitchtip.yaml --profile glitchtip up -d glitchtip
```

Open `http://localhost:8090`, create the organization and project, and put its DSN in the untracked local environment as `GLITCHTIP_DSN`. Keep `GLITCHTIP_SECRET_KEY` and the database password out of Git. When testing ingestion, use a synthetic exception; stop with the same Compose files and `down` (do not add `-v` unless intentionally deleting the tracker database).

## Kubernetes and AWS

The official Helm chart is `glitchtip` version `9.2.0` from `https://gitlab.com/api/v4/projects/16325141/packages/helm/stable`; the project values are in `helm/glitchtip/`. The EKS values require the `glitchtip-django-secret` (key `SECRET_KEY`) and `glitchtip-database-url` (key `DATABASE_URL`) Kubernetes Secrets. Provision them from AWS Secrets Manager through the established secret delivery path before syncing the Argo CD application. The chart's authenticated Valkey deployment is used for its task/cache backend.

Cloud ingress is disabled in the chart values. Set a private DNS name and TLS at the existing ingress layer before using it; `errors.example.invalid` is a deliberate placeholder. Configure a dedicated PostgreSQL 18 database with backup and retention policies before deployment. No Terraform apply, Argo sync, or cloud event-ingestion test was run here.

## Data handling and status

The Compose overlay passes `GLITCHTIP_DSN` to backend containers when configured; blank DSNs leave SDKs disabled. The language-specific SDK initialization, event sanitization, app release metadata, and synthetic ingestion test are not yet implemented. Do not treat this deployment scaffold as a completed SDK integration.

The OTel/Grafana stack remains responsible for metrics, logs, and traces. GlitchTip is reserved for grouped application errors and releases. Do not send secrets, request bodies, authorization data, or raw payment/customer data.
# Audit status

The React web app, fulfillment NestJS service, four Spring services, payments Go service, and AI/analytics FastAPI services initialize the GlitchTip-compatible SDK. Browser and server events use separate DSN variables. The event hooks remove request, user, context, extra, breadcrumb, message, and transaction payloads and redact exception text. Trace sampling is disabled. This is a conservative baseline; review service-specific tags and scrubbers before enabling event delivery.

The Helm chart is pinned to 9.2.0 and app image 7.0.0. Cloud ingress remains disabled and the host is a placeholder. Provision database, Django, Valkey, and client DSNs through secrets before enabling an environment. Do not mark deployment complete until a synthetic event is observed and retention/backup/alerting are confirmed.
