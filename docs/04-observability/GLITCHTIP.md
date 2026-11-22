# GlitchTip error tracking

## Selected release

- GlitchTip image: `glitchtip/glitchtip:7.0.0` (exact stable tag; latest stable observed on 2026-11-18).
- Official Helm chart: `9.2.0`, appVersion `7.0.0` (chart digest `sha256:a14b1face40ee3631ae017d5ed213ee19536f94e5d568cf06675eb9e8b8bf8f5`).
- Local database: PostgreSQL `18-alpine` by default (`POSTGRES_VERSION`); GlitchTip 7.0 requires PostgreSQL 15 or newer. The official installation page still says 14+, so the 7.0 release note takes precedence.
- The Kubernetes deployment uses authenticated Valkey. Local Compose reuses its authenticated Redis service.

## Local Compose

This is a separate, opt-in service set and stores PostgreSQL data in the Compose-managed `glitchtip_pgdata` volume (named `<compose-project>_glitchtip_pgdata`, or `microservices-architecture_glitchtip_pgdata` with this repository's default project name). Keeping Compose's default volume naming preserves existing local data and lets `down -v` remove it intentionally. It binds only to loopback on port 8090. Use synthetic data.

The PostgreSQL 18 image mounts its data volume at `/var/lib/postgresql`. This configuration is for a new PostgreSQL 18 data directory; it does not migrate an existing PostgreSQL 16 volume. Back up and migrate existing data with `pg_dump`/restore before switching.

```powershell
$env:GLITCHTIP_DB_PASSWORD = '<URL-safe local password>'
$env:GLITCHTIP_SECRET_KEY = '<generated random secret>' # Optional pwsh command: [Convert]::ToBase64String([System.Security.Cryptography.RandomNumberGenerator]::GetBytes(48))
$env:GLITCHTIP_ADMIN_EMAIL = 'glitchtip@microservices-architecture.dev'
$env:GLITCHTIP_ADMIN_PASSWORD = '<strong local password>'
./scripts/start-glitchtip-compose.ps1
```

Open `http://localhost:8090` and sign in with the configured admin email and password. GlitchTip runs migrations and idempotently recreates the `microservices-development` organization and service projects every time its container starts. Use the start script for a complete startup: it waits for GlitchTip, obtains the current project DSNs, stores them in the ignored local `.env`, rebuilds the frontend with its browser DSN, and starts/recreates backend services with their DSNs. Run it after changing the GlitchTip URL or after an intentional database reset. Compose waits for PostgreSQL and Redis before starting GlitchTip. Keep all passwords, DSNs, and `GLITCHTIP_SECRET_KEY` out of Git. When testing ingestion, use a synthetic exception. `docker compose down -v` now removes the managed database volume and its event history; the next run of the start script recreates the organization/projects and reconnects all services. This is configuration recovery, not data backup: back up the database if event history or user-created settings must survive a volume deletion.

## Kubernetes and AWS

The official Helm chart is `glitchtip` version `9.2.0` from `https://gitlab.com/api/v4/projects/16325141/packages/helm/stable`; the project values are in `helm/glitchtip/`. The EKS values require the `glitchtip-django-secret` (key `SECRET_KEY`) and `glitchtip-database-url` (key `DATABASE_URL`) Kubernetes Secrets. Provision them from AWS Secrets Manager through the established secret delivery path before syncing the Argo CD application. The chart's authenticated Valkey deployment is used for its task/cache backend.

Cloud ingress is disabled in the chart values. Set a private DNS name and TLS at the existing ingress layer before using it; `errors.example.invalid` is a deliberate placeholder. Configure a dedicated PostgreSQL 18 database with backup and retention policies before deployment. No Terraform apply, Argo sync, or cloud event-ingestion test was run here.

## Data handling and status

The Compose overlay accepts per-project DSNs from `.env`; blank DSNs leave SDK reporting disabled. The Minikube workflow provisions projects and DSNs automatically after GlitchTip is healthy. Use synthetic events to verify ingestion.

The OTel/Grafana stack remains responsible for metrics, logs, and traces. GlitchTip is reserved for grouped application errors and releases. Do not send secrets, request bodies, authorization data, or raw payment/customer data.
# Audit status

The React web app, fulfillment NestJS service, four Spring services, payments Go service, and AI/analytics FastAPI services initialize the GlitchTip-compatible SDK. Browser and server events use separate DSN variables. The event hooks remove request, user, context, extra, breadcrumb, message, and transaction payloads and redact exception text. Trace sampling is disabled. This is a conservative baseline; review service-specific tags and scrubbers before enabling event delivery.

The Helm chart is pinned to 9.2.0 and app image 7.0.0. Cloud ingress remains disabled and the host is a placeholder. Provision database, Django, Valkey, and client DSNs through secrets before enabling an environment. Do not mark deployment complete until a synthetic event is observed and retention/backup/alerting are confirmed.
