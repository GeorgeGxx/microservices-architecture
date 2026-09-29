# Cosmo Router hardening and capabilities

This page tracks the Router capabilities enabled by this repository and the prerequisites for capabilities intentionally left off. Redis is not a Cosmo Router dependency in this setup.

## Enabled and existing

| Capability | Current implementation |
|---|---|
| JWT verification | Router verifies presented Keycloak JWTs using the realm JWKS endpoint (`RS256`). Anonymous requests remain allowed globally for public catalog fields and health endpoints. Invalid supplied tokens are rejected. |
| Field authentication | Orders subgraph uses Federation v2.5 and `@authenticated` on order queries/mutations; the Router rejects unauthorized operations before subgraph fetches. Spring service authorization remains authoritative as defense in depth. |
| Scope authorization | Not configured. Keycloak roles are in the nested `realm_access.roles` claim; Cosmo `scope_claim` only reads top-level claims. Do not apply `@requiresScopes` until an explicit top-level OAuth scope contract is established. |
| CORS and request headers | Origins remain restricted per deployment values. `Authorization`, idempotency, W3C trace context and `X-Correlation-ID` are propagated; credentials and query variables are not logged. |
| Query and body abuse limits | Body is capped at 1 MB, headers at 1 MiB, GraphQL depth at 12, total fields at 250, root fields at 12, root aliases at 5, parser depth at 40 and parsed fields at 500. A 1024-entry in-memory complexity cache avoids repeated calculations. |
| Rate limiting | Existing Nginx edge limit is 20 requests/second per peer with burst 30. No second Router limiter is configured, since Cosmo's distributed limiter requires Redis and Redis is intentionally excluded from this Router design. |
| Resilience | 20 s subgraph request, 3 s dial and 15 s response-header timeouts plus bounded jitter retries (2 attempts). Retries are safe for GraphQL queries; Cosmo does not retry mutations. Circuit breaker remains enabled in cloud production overlays and disabled in local profiles to avoid tripping during cold starts. |
| Performance | Cosmo's request deduplication and query-plan cache are built in. The complexity calculation cache is configured above. |
| Observability | Prometheus metrics and OTLP traces are already enabled. Router and subgraph JSON access logs now include operation name/type/hash, not query variables or credentials; Alloy/Loki collects container logs. |
| Live configuration | Router config watch is enabled at 10 seconds. The Helm chart mounts the ConfigMap read-only at both config paths and has readiness/liveness probes. |
| Mesh security | In Kubernetes, Istio sidecars enforce mesh mTLS while the Router calls in-cluster HTTP service addresses. TLS terminates at the mesh proxy. Docker Compose is a local, non-mesh profile and uses its private network. |
| Deployment | The repository has a Cosmo Helm chart and Minikube manifest; cloud workloads are behind the Istio ingress and mesh policies. |

## Deliberately not enabled yet

- **Persisted-operation-only mode:** there is no reviewed, versioned allowlist generated from the storefront and test clients. Enabling this now would reject current Postman, smoke, and frontend GraphQL calls. Add the operation registry and client rollout before blocking non-persisted operations.
- **`@requiresScopes`:** align Keycloak access-token claims to a top-level scope claim and define scopes/roles for each operation first. The service-level role checks continue to protect order data.
- **WebSocket/SSE through Cosmo and EDFS:** the current order/catalog subgraphs declare no GraphQL `Subscription` root. The notification service already provides SSE independently. Add an event schema, authorization/filtering rules, and client contract before connecting Kafka through EDFS.
- **Custom Go modules:** no Router-specific Go extension requirement currently exists. The built-in JWKS, authorization, header, logging, traffic-shaping, and telemetry features cover current requirements without maintaining a custom Router binary.
- **Router-level Redis rate limiting or response cache:** excluded by design. Nginx rate limiting is active; Cosmo response cache remains experimental and would introduce Redis/data-consistency considerations.
- **Cache warmup:** the current static execution config is generated from SDL, but there is no persisted-operation source to warm from. Router query-plan caching remains enabled and warms naturally from traffic.

## Configuration sources

Keep these aligned when changing Router behavior:

- `cosmo-router/router.yaml` — Docker Compose runtime configuration.
- `cosmo-router/subgraphs/orders.graphql` — local Federation composition source of truth.
- `helm/charts/cosmo-router/{values.yaml,templates/configmap.yaml}` — Helm/Argo CD deployments.
- `k8s/minikube/services/cosmo-router.yaml` — standalone Minikube manifest and embedded composition SDL.

After SDL changes, regenerate the execution config and Helm asset with `scripts/build-cosmo-router-config.ps1`. Validate behavior in Compose and Minikube before rollout; the manifest edits alone do not deploy changes to an active cluster.
