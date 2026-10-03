# 📄 ADR-006: Zero-Trust Service Mesh & Canary Traffic Management with Istio

* **Status:** 🟢 ACCEPTED
* **Deciders:** Enterprise Architect, Solution Architect, Platform/SRE Lead, SecOps Lead
* **Date:** 2026-02-20
* **Technical Story:** Service Mesh, Strict mTLS, and Zero-Downtime Canary Rollouts

---

## 🎯 Context & Problem Statement

In microservices architectures, default flat Kubernetes networks permit unrestricted pod-to-pod communication in plain-text HTTP. Furthermore, blue/green and canary deployments require sophisticated L7 traffic routing (e.g. weighted traffic splits 90/10, header matching, fault injection) that standard Kubernetes Services and Ingress controllers cannot provide.

We require a service mesh that enforces:
1. End-to-end Zero-Trust security with mutual TLS (mTLS) and cryptographic workload identities.
2. Declarative Layer 7 traffic routing and Canary releases via VirtualServices and DestinationRules.
3. Transparent observability sidecars producing distributed tracing headers.
4. L3/L4 NetworkPolicies restricting lateral movement between namespaces.

---

## ⚖️ Decision Drivers

1. **Zero-Trust Security Compliance:** All in-cluster traffic must be encrypted with automatic certificate rotation.
2. **Canary Deployment Precision:** Shift production traffic gradually (e.g. 10% canary $\rightarrow$ 100% full release) with automated rollback capability.
3. **Observability Mesh Integration:** Native telemetry emission to Prometheus, Kiali, and Jaeger/Tempo.
4. **Ecosystem Maturity:** Battle-tested CNCF graduated technology with broad enterprise adoption.

---

## 🔍 Considered Alternatives

* **Option 1 (Baseline):** Plain Kubernetes Services + Nginx Ingress Controller
* **Option 2:** Istio Service Mesh (Envoy sidecars)
* **Option 3:** Linkerd 2 (Rust-based micro-proxy)

---

## 📊 Pugh Multi-Criteria Decision Matrix

| Evaluation Criteria | Weight (1-5) | Option 1: Nginx Ingress | Option 2: Istio Service Mesh | Option 3: Linkerd 2 |
| :--- | :---: | :---: | :---: | :---: |
| **Strict mTLS & Workload Identity** | 5 | 0 (Baseline: none) | **+1** (Strict mTLS via Citadel SPIFFE) | +1 (Native mTLS) |
| **L7 Canary Traffic Splitting (90/10)** | 5 | 0 (Baseline: primitive) | **+1** (Advanced VirtualService weights) | 0 (Requires SMI/Argo) |
| **Visual Mesh Topology (Kiali)** | 4 | 0 (Baseline) | **+1** (Kiali real-time graph) | 0 (Basic Linkerd Viz) |
| **Distributed Tracing Injection** | 4 | 0 (Baseline: app code) | **+1** (Envoy transparent header inject) | +1 (Trace propagation) |
| **Resource Overhead** | 3 | 0 (Baseline: lightweight) | **-1** (~50MB per Envoy sidecar) | 0 (Lighter Rust proxy) |
| **Weighted Total** | - | **0.00** | **+15 (WINNER)** | +9.00 |

---

## 💡 Decision Outcome

Chosen option: **Option 2 (Istio Service Mesh)**.

### Positive Consequences
* **Automated Mutual TLS:** PeerAuthentication policy enforces `STRICT` mTLS across the `dev`, `staging`, and `production` namespaces.
* **Canary Deployment Precision:** VirtualServices split traffic (90% stable / 10% canary) allowing zero-downtime testing of new versions.
* **Network Segmentation:** Zero-Trust NetworkPolicies restrict ingress/egress, isolating `dev` microservices from untrusted namespaces.
* **Visual Diagnostics:** Kiali dashboard (`:20001/kiali`) provides real-time traffic flow visualization and health indicators.

### Negative Consequences / Trade-offs
* Pod Security Admission (PSA) requires `privileged` namespace enforcement on sidecar-injected namespaces because `istio-init` requires `NET_ADMIN` and `NET_RAW` to configure iptables. Application containers remain unprivileged and non-root.
