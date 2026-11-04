# Kubernetes Platform Security & Zero-Trust Mesh Architecture

## 1. Pod & Container Hardening Baseline

All application charts under `helm/charts/*` and `helm/microservices-umbrella/` are validated against OPA Conftest (`devsecops/policies/conftest/`) and OPA Gatekeeper (`devsecops/policies/gatekeeper/`) to enforce:

- **Non-Root Execution:** `runAsNonRoot: true`, explicit `runAsUser: 65532` (or `10001`), and `fsGroup: 65532`.
- **Privilege & Capability Dropping:** `allowPrivilegeEscalation: false`, `privileged: false`, and `capabilities.drop: ["ALL"]`.
- **Immutable Root Filesystem:** `readOnlyRootFilesystem: true` with explicit `emptyDir` mounts for `/tmp` and runtime caches.
- **Dedicated ServiceAccounts:** Every microservice runs under its own least-privilege `ServiceAccount` (`automountServiceAccountToken: false` unless required) - never `default`.
- **Resource Requests, Limits, Probes & PDBs:** All production deployments define CPU/memory `requests` and `limits`, `livenessProbe`, `readinessProbe`, `startupProbe`, `PodDisruptionBudget`, and `HorizontalPodAutoscaler` / KEDA `ScaledObject`.

---

## 2. Zero-Trust Network & Service Mesh Controls

1. **Istio mTLS (`STRICT`):**
   - `k8s/istio/peer-authentication-prod.yaml` enforces cluster-wide `STRICT` mutual TLS across all microservices. Scrape exception ports for unauthenticated Prometheus scraping are restricted via L3/L4 NetworkPolicies and L7 AuthorizationPolicies.
2. **L7 AuthorizationPolicies & Least-Privilege Access:**
   - `k8s/istio/03-authorization-policies-prod.yaml` enforces a default-deny stance (`default-deny-all`) and explicitly authorizes service-to-service calls based on cryptographic SPIFFE identities (`cluster.local/ns/<namespace>/sa/<serviceaccount>`).
3. **Kubernetes L3/L4 NetworkPolicies:**
   - Default-deny ingress/egress and explicit east-west allow-lists in `helm/microservices-umbrella/templates/network-policies.yaml` restrict pod traffic to authorized upstream/downstream services and database ports (`5432`-`5438`, `6379`, `9092`).
4. **GraphQL Edge Hardening (WunderGraph Cosmo Router):**
   - In production (`values-eks-prod.yaml`, `values-aks-prod.yaml`, `values-gke-prod.yaml`), GraphQL introspection and playground are disabled (`introspection: false`, `playgroundEnabled: false`), query depth is restricted (<= 12), and circuit breakers are enabled.

---

## 3. 3-Phase Enterprise Production Hardening Standards

To satisfy the most demanding compliance benchmarks (**CIS Kubernetes Benchmark 5.2**, **NIST SP 800-190**, **PCI-DSS**, and **SOC 2 Type II**), the platform implements three defense-in-depth hardening phases:

### Phase 1: Pod Hardening & Pod Security Standards (Restricted Profile)
- **Kubernetes Pod Security Admission (PSA):**
  - Production namespaces (`production`, `prod`) strictly enforce `pod-security.kubernetes.io/enforce: restricted` (`k8s/common/namespaces-prod.yaml`).
- **Gatekeeper OPA Policy-as-Code:**
  - `devsecops/policies/gatekeeper/templates/k8s-pod-security-restricted.yaml` & `constraints/enforce-pod-security-restricted.yaml` audit and block any workload attempting privilege escalation, root execution, or Linux capability retention.
- **Zero-Privilege Sidecars via Istio CNI:**
  - Configured via `k8s/istio/istio-cni.yaml`. By replacing the `istio-init` container with a cluster-level CNI DaemonSet, application pods eliminate the requirement for elevated `NET_ADMIN` and `NET_RAW` capabilities, running cleanly under the `restricted` PSA profile.

### Phase 2: Secrets & Identities (Workload Identity & External Secrets)
- **ClusterSecretStore with Kubernetes Native Auth:**
  - `k8s/common/vault/vault-k8s-clustersecretstore.yaml` connects External Secrets Operator (ESO) to HashiCorp Vault using short-lived Kubernetes ServiceAccount JWTs, eliminating static root tokens.
- **Cloud Federated Workload Identities:**
  - **Azure AKS:** `k8s/aks/vault/external-secrets-azure-workload-identity.yaml` integrates with Azure Key Vault using federated Azure Workload Identity (client-id annotation).
  - **AWS EKS:** `k8s/eks/vault/external-secrets-aws-irsa.yaml` integrates with AWS Secrets Manager using IAM Roles for Service Accounts (IRSA).
- **Automated Rotation & Reconciliation:**
  - `k8s/common/vault/microservices-secrets-sync.yaml` enforces automated 1-hour secret rotation (`refreshInterval: 1h`) and drift remediation (`creationPolicy: Owner`).

### Phase 3: Edge Security, WAF, TLS & Container Supply Chain
- **Automated TLS 1.3 Lifecycle:**
  - `k8s/common/cert-manager/cluster-issuers.yaml` provisions ACME Let's Encrypt Production and Staging `ClusterIssuer` instances with automated 90-day certificate issuance and 30-day pre-expiry renewal.
- **Perimeter WAF & OWASP Security Headers:**
  - `k8s/istio/08-edge-security-waf.yaml` configures Istio Ingress Gateway with:
    - Strict HTTP security headers (`Strict-Transport-Security: max-age=31536000; includeSubDomains; preload`, `X-Content-Type-Options: nosniff`, `X-Frame-Options: DENY`, `X-XSS-Protection`, `Referrer-Policy`, and `Content-Security-Policy`).
    - Local rate limiting token bucket (100 req/min with a 200-burst ceiling) protecting against brute force and Layer-7 DDoS attacks.
- **Container Supply Chain Verification (Cosign & Trivy):**
  - The active Gatekeeper constraint `enforce-image-signatures` blocks the mutable tags `:latest`, `:dev`, and `:snapshot`, but its `enforceDigest` setting is `false`, so it does not require `@sha256` digests. The policy does not query Cosign signatures. CI verifies the signed supply-chain manifest against `devsecops/compliance/cosign/cosign.pub` with transparency-log checks enabled by default, but per-image signing and signature admission verification are not yet configured.

---

## 4. Service Mesh Sidecar Injection Guidelines

To prevent resource leakage, startup race conditions, and namespace degradation in Kiali, workloads are classified into sidecar injection profiles:

| Workload Type | Sidecar Injection (`sidecar.istio.io/inject`) | Justification |
| :--- | :---: | :--- |
| **Stateless Microservices** (`orders`, `inventory`, `payments`, `fulfillment`, `analytics`, `products`, `router`, `frontend`) | **`true` (Enabled)** | Core service mesh participants requiring mTLS encryption, L7 telemetry, tracing, and circuit breaking. |
| **Batch Jobs & CronJobs** (`demand-model-training-scheduler`, database backup/export jobs) | **`false` (Disabled)** | **Prevents Envoy lifecycle deadlock**: Envoy does not exit when batch workloads complete (`exit 0`), which leaves pods stuck in `0/1 Completed` or `NotReady` and triggers cluster alerts. |
| **Database Migrations** (Flyway, Liquibase, Alembic) | **`false` (Disabled)** | **Eliminates startup race condition**: Migration scripts running before Envoy proxy finishes listener sync encounter connection drops. |
| **Stateful Data Tier** (PostgreSQL, Kafka, Redis) | **`false` (Disabled)** | Bypasses proxy buffering and serialization overhead for persistent connection pools and binary protocols. |
| **Observability Collectors** (Prometheus, Tempo, Loki) | **`false` (Disabled)** | Prevents circular dependencies between the mesh proxy and the collectors monitoring the proxy. |
