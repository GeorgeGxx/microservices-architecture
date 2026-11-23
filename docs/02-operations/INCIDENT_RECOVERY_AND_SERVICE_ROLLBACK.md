# Incident Recovery and Service Rollback

This runbook covers a single-service release regression and local recovery drills. It does not authorize a production deployment or cloud failover. The repository currently targets an umbrella Helm release in Argo CD; recovery tooling restores only the affected service's previous image override.

## Release rollback for one service

1. Declare the incident, identify the affected service and environment, and pause further promotion. Keep the production environment's manual approval gate in place.
2. Check the deployed image tag or digest and the last known healthy SemVer release. Docker Hub retention is configured for the two latest release tags, so confirm the rollback tag still exists before changing GitOps state.
3. Prefer a Git revert of the service's image tag change so Git remains authoritative. For an immediate Argo CD recovery, use the existing deployment workflow's service-scoped rollback, which snapshots and restores only that service's prior image override on each targeted Application.
4. Do not use an umbrella Application revision rollback for a single service: that can restore unrelated chart values and images. Do not edit or sync both dataplanes unless both are part of the incident.
5. Verify the affected workload is Ready, exercise its health and business smoke checks, confirm dependency/event processing, and monitor service-specific error and latency dashboards before resuming promotion.

Example version change for a release PR (adjust the repository's values file for the target environment):

```yaml
payments-service:
  image:
    tag: "1.0.0" # restore the previous healthy release after 1.1.0
```

For Argo CD CLI incident work, first inspect the relevant application and parameters. Only update the service image parameter; do not run `argocd app rollback` against the umbrella application for an isolated service incident.

## Database and state recovery

The checked-in BCDR simulation supports local Docker Compose backup verification and isolated restores. It does not establish production RPO/RTO or prove that cloud snapshots, cross-region replicas, immutable storage, credentials, and network routes are configured. Confirm the environment's recovery point and target with the database owner before any restore. Restore into an isolated target first and validate schema, row-level business invariants, and application compatibility before redirecting traffic.

Run the local drill only against the local Compose stack:

```powershell
.\scripts\bcdr-simulation.ps1 -Action VerifyBackups -Component All
```

The drill verifies PostgreSQL dump integrity and isolated restore, Kafka retained-message replay, and MLflow SQLite/artifact consistency. It may create temporary local containers, databases, topics, and files. Inspect the script and clean up the generated local drill artifacts when done. Do not run its `SimulateFailover` action against a shared or production cluster as part of this runbook.

## Argo CD application boundary

`argocd/application-*.yaml` currently points to `deploy/helm/microservices-umbrella`. The umbrella chart owns shared configuration, secrets, network policy, and observability resources as well as service charts. Creating one Argo CD Application per service today would cause overlapping ownership of shared objects and could trigger pruning conflicts.

The release workflow already limits image builds, GitOps image updates, and emergency image override restoration to changed services. Argo CD uses `ApplyOutOfSyncOnly=true`, reducing unnecessary resource writes during sync. A future per-service ApplicationSet should follow a separate migration that extracts shared objects into a foundation chart/Application, defines explicit ownership, validates rendered manifests for duplicates, and tests prune behavior in a disposable cluster before enabling automated sync.

## Recovery objectives and evidence

The architecture document lists target RTO/RPO values. These are design goals, not measured service guarantees. Record actual recovery time, recovery point, image digest, database restore point, validation evidence, and approver after each drill. Define environment-specific RTO/RPO with service owners before treating the targets as operational commitments.
