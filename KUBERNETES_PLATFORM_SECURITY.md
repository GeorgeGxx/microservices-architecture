# Kubernetes Platform Security & Zero-Trust Mesh Architecture

## 1. Pod & Container Hardening Baseline

All application charts under `helm/charts/*` and `helm/microservices-umbrella/` are validated against OPA Conftest (`devsecops/policies/conftest/`) and OPA Gatekeeper (`devsecops/policies/gatekeeper/`) to enforce:

- **Non-Root Execution:** `runAsNonRoot: true`, explicit `runAsUser: 1001` (or `10001`), and `fsGroup: 2000`.
- **Privilege & Capability Dropping:** `allowPrivilegeEscalation: false`, `privileged: false`, and `capabilities.drop: ["ALL"]`.
- **Immutable Root Filesystem:** `readOnlyRootFilesystem: true` with explicit `emptyDir` mounts for `/tmp` and runtime caches.
- **Dedicated ServiceAccounts:** Every microservice runs under its own least-privilege `ServiceAccount` (`automountServiceAccountToken: false` unless required) — never `default`.
- **Resource Requests, Limits, Probes & PDBs:** All production deployments define CPU/memory `requests` and `limits`, `livenessProbe`, `readinessProbe`, `startupProbe`, `PodDisruptionBudget`, and `HorizontalPodAutoscaler`.

---

## 2. Zero-Trust Network & Service Mesh Controls

1. **Istio mTLS (`STRICT`):**
   - `k8s/istio/01-peer-authentication.yaml` enforces cluster-wide `STRICT` mutual TLS across all microservices.
2. **L7 AuthorizationPolicies & JWT Authentication:**
   - `k8s/istio/03-jwt-authorization.yaml` validates Keycloak OIDC JWT signatures at the mesh layer and restricts service-to-service traffic by SPIFFE identity and HTTP path/method.
3. **Kubernetes L3/L4 NetworkPolicies:**
   - Default-deny ingress/egress and explicit east-west allow-lists in `helm/microservices-umbrella/templates/networkpolicies.yaml` restrict pod traffic to authorized upstream/downstream services and database ports (`5432`–`5438`, `6379`, `9092`).
4. **GraphQL Edge Hardening (WunderGraph Cosmo Router):**
   - In production (`values-eks-prod.yaml`, `values-aks-prod.yaml`, `values-gke-prod.yaml`), GraphQL introspection and playground are disabled (`introspection: false`, `playgroundEnabled: false`), and circuit breakers are enabled.
