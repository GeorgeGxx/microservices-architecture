# 📄 ADR-013: Zero-Trust Istio Security Hardening, Strict mTLS, and Least-Privilege Authorization

* **Status:** 🟢 ACCEPTED
* **Deciders:** Istio Service Mesh Architect, Senior DevSecOps Engineer, Kubernetes Security Specialist, Lead Architect
* **Date:** 2026-10-31
* **Technical Story:** Elimination of Port-Level mTLS Downgrades, Enforcement of Default-Deny Authorization, and Edge Gateway Defense

---

## 🎯 Context & Problem Statement

Prior to this audit, an inspection of Istio resources in `k8s/istio/peer-authentication-dev.yaml` and `peer-authentication-staging.yaml` revealed a critical security weakness:
Port-level `PERMISSIVE` mTLS exceptions were configured for ports 8001, 8002, 8003, 8004, 8005, 8085, 8086, and 8087 under the pretext of Prometheus metrics scraping.

Because these ports are the **primary business application ports** of each service, this configuration effectively downgraded mutual TLS from `STRICT` to `PERMISSIVE` across all east-west microservice communications, allowing unauthenticated, unencrypted requests to penetrate the mesh. Furthermore:
1. Production lacked dedicated `PeerAuthentication` and `DestinationRule` manifests in `k8s/istio/`.
2. No `AuthorizationPolicy` resources existed, permitting any compromised workload to invoke any internal microservice.
3. The edge `02-gateway.yaml` exposed Keycloak administrative endpoints (`/admin/`) to the public internet on port 80 HTTP without TLS redirection.

---

## 🛡️ Architectural Decisions & Hardening Strategy

### 1. Elimination of Application Port mTLS Exceptions
- **Decision:** Remove all `portLevelMtls` exceptions on application business ports (8001–8087) from `PeerAuthentication`.
- **Metrics Architecture:** Microservice metrics (`/actuator/*/prometheus`) are scraped securely by Prometheus over Envoy sidecars using the mesh's native `ISTIO_MUTUAL` certificates, or via Envoy's dedicated telemetry port 15090 (`/stats/prometheus`).
- **Cosmo Router Port 9090:** The only justified `PERMISSIVE` exception is port 9090 on Cosmo Router, which is a dedicated Prometheus metrics listener completely separate from the GraphQL router port 8080.

### 2. Multi-Environment STRICT mTLS
- Dedicated `PeerAuthentication` resources enforce `mode: STRICT` across:
  - `dev` (`k8s/istio/peer-authentication-dev.yaml`)
  - `staging` (`k8s/istio/peer-authentication-staging.yaml`)
  - `production` and `prod` (`k8s/istio/peer-authentication-prod.yaml`)

### 3. Least-Privilege AuthorizationPolicies (Default-Deny)
- Deploy declarative `AuthorizationPolicy` resources implementing:
  1. **Default-Deny:** An empty `spec: {}` policy in each namespace blocking all inter-service traffic by default.
  2. **Ingress-to-Edge Allow:** Only Istio Ingress Gateway (`istio-ingressgateway-service-account`) and Frontend are authorized to call `cosmo-router:8080` (`/graphql*`, `/health*`).
  3. **Router-to-Subgraphs Allow:** Only `cosmo-router-sa` is authorized to call the federated subgraphs (`products-service`, `orders-service`, `inventory-service`, `notification-service`, `payments-service`, `fulfillment-service`, `analytics-service`).
  4. **Service-to-Service Allow:** Only `orders-service-sa` is permitted to invoke downstream services (`inventory-service:8001`, `payments-service:8085`, `notification-service:8002`).
  5. **Observability Allow:** Scrapers in `observability` and `istio-system` namespaces are explicitly authorized to access telemetry paths (`/actuator*`, `/metrics*`, `/stats/prometheus*`).

### 4. Edge Gateway Defense & Administrative Isolation
- **Removal of Public `/admin/` Route:** Keycloak administration console is removed from the edge Gateway (`k8s/istio/02-gateway.yaml` and `02-gateway-prod.yaml`). Keycloak console access must be conducted via internal port-forwarding, VPN, or private administrative ingress.
- **HTTPS Enforcement:** Production edge gateway (`02-gateway-prod.yaml`) enforces automatic HTTP-to-HTTPS redirection (`httpsRedirect: true`) on port 80 and terminates TLS 1.3/1.2 on port 443 with explicit domain matching (`msa.example.com`).

### 5. DestinationRule Resilience
- DestinationRules across all environments now explicitly define:
  - `trafficPolicy.tls.mode: ISTIO_MUTUAL`
  - Connection pooling (TCP max connections: 1024–2048, HTTP pending request limits)
  - Circuit breakers with outlier detection (`consecutive5xxErrors: 3`, ejection time: 30s)

---

## 💡 Consequences

### Positive Consequences
- **True Zero-Trust:** All internal service communications are cryptographically authenticated and encrypted with SPIFFE certificates.
- **Lateral Movement Containment:** An attacker compromising one microservice cannot pivot to unauthorized backend databases or sibling microservices.
- **Perimeter Hardening:** Administrative consoles are isolated from the internet.

### Negative Consequences / Operational Considerations
- Any new microservice or inter-service API call must be explicitly declared in the corresponding environment's `AuthorizationPolicy`.
