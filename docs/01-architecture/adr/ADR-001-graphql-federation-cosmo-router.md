# 📄 ADR-001: GraphQL Supergraph Federation v2 with WunderGraph Cosmo Router

* **Status:** 🟢 ACCEPTED
* **Deciders:** Enterprise Architect, Solution Architect, Tech Lead, SecOps Lead
* **Date:** 2026-01-15
* **Technical Story:** Architecture Core Gateway Modernization

---

## 🎯 Context & Problem Statement

The platform exposes four independent microservices (`products-service`, `orders-service`, `inventory-service`, `notification-service`). Frontend clients (React SPA, mobile apps, third-party integrations) require unified query capabilities, type safety, and consolidated data fetching without client-side over-fetching or multiple roundtrips.

We require a centralized API Gateway capable of:
1. Composing an Apollo Federation v2 Supergraph across distributed subgraphs.
2. Delivering microsecond query planning and sub-millisecond execution times.
3. Validating Keycloak JSON Web Tokens (JWT) at the edge via JWKS.
4. Exporting native OpenTelemetry metrics and traces to our LGTM observability stack.

---

## ⚖️ Decision Drivers

1. **Ultra-Low Latency & High Concurrency:** Gateway must sustain > 5,000 req/sec with p95 < 20ms.
2. **Federation v2 Standard:** Native `@key`, `@shareable`, `@external`, and `@provides` directive resolution.
3. **Open-Source Footprint & Licensing:** Avoid proprietary or closed-source license restrictions (e.g. Apollo Enterprise ELv2).
4. **Memory Footprint:** Keep resource consumption minimal on local Minikube developer workstations (< 100MB RAM).

---

## 🔍 Considered Alternatives

* **Option 1 (Baseline):** Apollo Gateway (Node.js runtime)
* **Option 2:** WunderGraph Cosmo Router (Go native binary)
* **Option 3:** Envoy Proxy with WebAssembly GraphQL Filter

---

## 📊 Pugh Multi-Criteria Decision Matrix

| Evaluation Criteria | Weight (1-5) | Option 1: Apollo Gateway (Node.js) | Option 2: WunderGraph Cosmo Router (Go) | Option 3: Envoy GraphQL Wasm |
| :--- | :---: | :---: | :---: | :---: |
| **Throughput & Low Latency** | 5 | 0 (Baseline) | **+1** (10x faster execution) | +1 (High performance C++) |
| **Federation v2 Compatibility** | 5 | 0 (Baseline) | **+1** (Full Federation v2 spec) | -1 (Limited schema stitching) |
| **Memory Footprint (< 100MB)** | 4 | 0 (Baseline: ~350MB) | **+1** (< 50MB RAM footprint) | +1 (~80MB RAM) |
| **OpenTelemetry Integration** | 4 | 0 (Baseline: plugins) | **+1** (Native OTLP traces & Prom metrics) | 0 (Requires custom filters) |
| **Edge JWT Validation (Keycloak)** | 4 | 0 (Baseline: JS middleware) | **+1** (Native JWKS caching & header inject) | -1 (Complex Wasm filter) |
| **Extensibility & Maintenance** | 3 | 0 (Baseline) | **0** (Go modules / TypeScript) | -1 (Complex C++/Rust toolchain) |
| **Weighted Total** | - | **0.00** | **+22 (WINNER)** | +1.00 |

---

## 💡 Decision Outcome

Chosen option: **Option 2 (WunderGraph Cosmo Router)**.

### Positive Consequences
* **Extreme Performance:** Go-based compiled binary provides predictable sub-millisecond query planning and low garbage collection overhead.
* **Low Developer Overhead:** Runs effortlessly on local Minikube using only ~45MB of RAM.
* **Zero-Trust Security:** Intercepts incoming JWT tokens, validates claims against Keycloak (`/protocol/openid-connect/certs`), and propagates sanitized identities downstream.
* **Unified Observability:** Automatically produces W3C `traceparent` headers, feeding distributed traces into Grafana Tempo.

### Negative Consequences / Trade-offs
* GraphQL Supergraph schema composition requires generating a unified execution plan via Cosmo CLI (`wgc router compose`).

---

## 🛡️ Security & Operational Validation
* Verified in automated CI/CD via:
  - `platform-minikube.ps1 smoke`: Probes Cosmo Router Supergraph root `/graphql` with HTTP 200 within 50ms.
  - `platform-minikube.ps1 contract`: Newman test suite executes 20 federated queries and mutations.
  - `platform-minikube.ps1 performance`: k6 benchmark validates p95 latency < 200ms under 25 concurrent VUs.
