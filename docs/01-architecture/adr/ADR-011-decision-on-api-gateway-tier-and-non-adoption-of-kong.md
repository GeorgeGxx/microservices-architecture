# 📄 ADR-011: Decision on API Gateway Tier and Non-Adoption of Kong Gateway

* **Status:** 🟢 ACCEPTED
* **Deciders:** Principal Cloud Platform Architect, Senior DevSecOps Engineer, Istio Service Mesh Architect, Lead SRE
* **Date:** 2026-10-31
* **Technical Story:** Edge Gateway Architecture, GraphQL Federation Ingress, and Reverse Proxy Consolidation

---

## 🎯 Context & Problem Statement

The platform currently operates an edge-to-mesh ingress architecture composed of an external Layer 4 Network Load Balancer (AWS NLB / Azure SLB / GCP NLB), an **Istio Ingress Gateway** (Envoy reverse proxy), and **WunderGraph Cosmo Router v2** for GraphQL Federation.

As enterprise microservices grow, teams frequently consider introducing dedicated API management gateways such as **Kong Gateway**. We must evaluate whether introducing Kong Gateway into the request pipeline is justified, or whether Istio Ingress Gateway and Cosmo Router provide sufficient capabilities without the added latency, licensing cost, and operational complexity of an additional proxy hop.

---

## 🔍 Comprehensive Evaluation of Kong Gateway Adoption

### 1. Specific Business and Technical Requirement
- **Requirement:** Expose a unified GraphQL Supergraph and selected REST APIs to external consumers (SPA storefront, mobile clients, external partners), enforce edge TLS, validate Keycloak JWTs, route requests to federated subgraphs, and apply rate limiting.
- **Analysis:** These requirements are fully satisfied by the current combination of CloudFront/AWS WAF (DDoS and perimeter filtering), Istio Ingress Gateway (L4/L7 routing, TLS termination, local Envoy rate limiting), and Cosmo Router (GraphQL Federation v2, JWKS token validation, query depth/complexity protection).

### 2. Why Istio and Cosmo Router Alone are Sufficient
- **Istio Ingress Gateway (Envoy):** Handles edge TLS termination, virtual hosting, path-based routing, HTTP/2 and gRPC transport, telemetry header propagation (`traceparent`), connection pooling, and edge EnvoyFilter local/global rate limiting.
- **Cosmo Router v2 (Go):** Provides sub-millisecond GraphQL Federation v2 query planning, schema validation, Keycloak JWKS JWT verification, field-level authorization, and depth/alias protection without Node.js overhead.
- **Sufficiency Conclusion:** Kong Gateway would merely duplicate routing, TLS, and token verification without adding new technical capabilities required by this platform.

### 3. Proposed Request Flow Comparison
- **Current Streamlined Architecture:**
  `Client` $\rightarrow$ `AWS CloudFront / WAF` $\rightarrow$ `AWS NLB (L4)` $\rightarrow$ `Istio Ingress Gateway (Envoy)` $\rightarrow$ `Cosmo Router (GraphQL Supergraph)` $\rightarrow$ `Envoy Sidecars (mTLS STRICT)` $\rightarrow$ `Subgraphs`.
- **Kong Layered Architecture (Rejected Alternative):**
  `Client` $\rightarrow$ `CloudFront` $\rightarrow$ `NLB` $\rightarrow$ `Kong Gateway` $\rightarrow$ `Istio Ingress Gateway` $\rightarrow$ `Cosmo Router` $\rightarrow$ `Envoy Sidecars` $\rightarrow$ `Subgraphs`.
  Adding Kong introduces an unnecessary proxy hop (extra network serialization, latency, and failure domain).

### 4. Authentication and Authorization Responsibilities
- **Authentication:** Edge JWT bearer token verification is executed by Cosmo Router against Keycloak OpenID Connect JWKS (`/realms/microservices-realm/protocol/openid-connect/certs`).
- **Authorization:** Workload-to-workload authorization is enforced by Istio `AuthorizationPolicy` using SPIFFE cryptographic workload identities (`cluster.local/ns/<ns>/sa/<serviceaccount>`).
- Introducing Kong would fragment identity verification across three layers (Kong, Cosmo Router, Istio).

### 5. TLS Termination Responsibilities
- External TLS (HTTPS on port 443) is terminated at the Istio Ingress Gateway using ACM/Kubernetes certificates (`microservices-tls-cert`).
- Internal mesh traffic uses automatic `STRICT` mutual TLS (mTLS) with 24-hour rotating SPIFFE certificates issued by Istio Citadel.
- Kong would add redundant TLS renegotiation or plain-text bridging within the cluster.

### 6. Rate Limiting Responsibilities
- Perimeter rate limiting is enforced by AWS WAFv2 and Istio `EnvoyFilter` (`ingress-local-ratelimit`).
- Query-level rate limiting and request complexity limits (max depth $\le 12$, max total fields $\le 250$) are enforced inside Cosmo Router.

### 7. Operational Complexity
- Introducing Kong requires managing Kong Custom Resource Definitions (KongPlugin, KongConsumer, KongIngress), a dedicated PostgreSQL database (or DB-less ConfigMaps), separate deployment lifecycles, and additional operator monitoring.
- Preserving Istio + Cosmo Router maintains a single, standard service mesh control plane with unified GitOps governance in Argo CD.

### 8. Performance Implications
- Each additional reverse proxy hop adds 1.5ms to 5.0ms of p95 latency and additional TCP buffer memory overhead.
- Cosmo Router in Go and Istio in Envoy provide high-concurrency throughput (> 10,000 req/s) with minimal memory footprint (< 100MB per replica).

### 9. Infrastructure and Licensing Costs
- Kong Enterprise carries substantial commercial licensing fees for developer portal, enterprise plugins, and multi-datacenter governance.
- Istio and WunderGraph Cosmo Router are open-source (Apache 2.0), avoiding recurring licensing costs and reducing cluster EC2 compute requirements by 4–8 vCPUs.

### 10. Security Implications
- Adding Kong expands the cluster attack surface (additional network listeners, plugins, RBAC privileges, and third-party Lua/Go modules).
- The existing architecture adheres to the Zero-Trust security model with fewer moving parts and verifiable least privilege.

---

## 💡 Decision Outcome

**Decision:** **Do NOT adopt Kong Gateway.**

The platform will standardize exclusively on:
1. **Istio Ingress Gateway (Envoy)** as the perimeter Layer 7 Ingress Gateway.
2. **Cosmo Router v2** as the dedicated GraphQL Federation Router.
3. **Keycloak** as the centralized OIDC Identity Provider.
4. **Istio Service Mesh (mTLS STRICT)** as the east-west Zero-Trust transport and authorization layer.

### Consequences

#### Positive Consequences
- **Zero Duplication:** No overlapping responsibilities for routing, authentication, or TLS.
- **Lower Latency:** Avoids 2–5ms extra network serialization latency on every incoming request.
- **Reduced Cost & Footprint:** Saves cloud compute and licensing overhead.
- **Architectural Simplicity:** Consistent policy enforcement across Kubernetes manifests, Helm values, and Argo CD GitOps pipelines.

#### Negative Consequences / Mitigation
- Advanced consumer subscription quotas or public developer portals (if required in future commercial SaaS tiers) must be integrated via custom Keycloak realm claims or Cosmo Router plugins rather than off-the-shelf Kong plugins.
