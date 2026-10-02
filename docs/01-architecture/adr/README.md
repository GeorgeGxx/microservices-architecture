# 📜 Architecture Decision Records (ADRs)

> [!TIP]
> 🧭 **[Enterprise Platform Hub](../../../README.md)** > **01. Architecture** > `docs/01-architecture/adr/`

---

## 🎯 What is an Architecture Decision Record (ADR)?

An **Architecture Decision Record (ADR)** captures a significant architectural decision along with its context, considered alternatives, Pugh decision matrix, and consequences. We adhere to the **MADR (Markdown Architectural Decision Records)** standard and evaluate options using multi-criteria weighted scoring.

### ADR Lifecycle States:
- 🟡 **PROPOSED:** Under review by Architecture & Tech Leads.
- 🟢 **ACCEPTED:** Approved, ratified, and currently active in codebase.
- 🔴 **DEPRECATED:** Replaced or no longer applicable.
- 🟣 **SUPERSEDED:** Replaced by a newer ADR (links to successor).

---

## 📑 Master Architecture Decision Index

| ID | Title | Status | Date | Decision Summary |
| :---: | :--- | :---: | :---: | :--- |
| **[ADR-001](./ADR-001-graphql-federation-cosmo-router.md)** | GraphQL Supergraph Federation v2 with Cosmo Router | 🟢 ACCEPTED | 2026-01 | Adopt WunderGraph Cosmo Router (Go) over Apollo Gateway for high throughput, low latency, and native OTel. |
| **[ADR-002](./ADR-002-database-per-service-pattern.md)** | Database-per-Service & Domain Bounded Contexts | 🟢 ACCEPTED | 2026-01 | Enforce isolated PostgreSQL instances per service to eliminate cross-service data coupling. |
| **[ADR-003](./ADR-003-event-driven-choreography-kafka.md)** | Asynchronous Event-Driven Choreography via Kafka (KRaft) | 🟢 ACCEPTED | 2026-01 | Use Apache Kafka with KRaft consensus for decoupled Saga compensation and order notifications. |
| **[ADR-004](./ADR-004-centralized-iam-keycloak-oidc.md)** | Centralized IAM & RBAC via Keycloak 26 (OIDC/PKCE) | 🟢 ACCEPTED | 2026-02 | Standardize user authentication, multi-tenant isolation, and JWT propagation with Keycloak. |
| **[ADR-005](./ADR-005-secret-management-hashicorp-vault.md)** | Zero-Trust Secret Management with HashiCorp Vault | 🟢 ACCEPTED | 2026-02 | Replace hardcoded credentials with Vault KV-v2 engine and dynamic Kubernetes secret injection. |
| **[ADR-006](./ADR-006-zero-trust-service-mesh-istio.md)** | Zero-Trust Service Mesh & Canary Traffic with Istio | 🟢 ACCEPTED | 2026-02 | Implement Envoy-based mutual TLS (mTLS), strict NetworkPolicies, and 90/10 Canary deployments. |
| **[ADR-007](./ADR-007-event-driven-autoscaling-keda.md)** | Event-Driven Autoscaling with KEDA | 🟢 ACCEPTED | 2026-03 | Scale microservice pods based on Kafka queue lag and Prometheus request rates beyond basic CPU/RAM HPA. |
| **[ADR-008](./ADR-008-telemetry-observability-lgtm-opentelemetry.md)** | OpenTelemetry & Full-Stack LGTM Telemetry Engine | 🟢 ACCEPTED | 2026-03 | Deploy Loki, Grafana, Tempo, and Prometheus with OTLP tracing to prevent vendor lock-in. |
| **[ADR-009](./ADR-009-multi-cloud-iac-terraform.md)** | Multi-Cloud Infrastructure as Code with Terraform | 🟢 ACCEPTED | 2026-03 | Structure modular Terraform for 4 target versions (Minikube, AWS EKS, Azure AKS, GCP GKE). |
| **[ADR-010](./ADR-010-disaster-recovery-and-business-continuity.md)** | Cross-Region Warm Standby & Business Continuity (BCDR) | 🟢 ACCEPTED | 2026-10 | Enforce cross-region warm standby, streaming replication, immutable S3 WAL archiving, and RTO < 15m / RPO < 1m. |

---

## 🛠️ ADR Template

When proposing a new architectural change, copy [`ADR-TEMPLATE.md`](./ADR-TEMPLATE.md) and fill out the Pugh Matrix evaluation criteria before requesting approval in the Architecture Guild.
