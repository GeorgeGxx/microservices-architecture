# Cell-Based Architecture & Database Sharding (Pillar 5)

## 1. Executive Overview

As part of **Level 5 Hyper-Scale (Amazon / Uber / Netflix)** engineering, our platform implements **Cell-Based Architecture (AWS Cell-Based Architecture Pattern)**. 

In traditional monolithic or shared microservice deployments, an infrastructure outage, bad deployment, or poison-pill transaction in a database causes a global cascading failure (100% blast radius). Under Cell-Based Architecture, the system is partitioned into independent, self-contained deployment units called **Cells** (e.g. `cell-alpha`, `cell-beta`).

```
                    +------------------------------------+
                    |        Cosmo Supergraph /          |
                    |        Istio Cell Router           |
                    +-----------------+------------------+
                                      |
                 +--------------------+--------------------+
                 | (Header: X-Cell-Id: cell-alpha)          | (Header: X-Cell-Id: cell-beta)
                 v                                         v
     +-----------------------+                 +-----------------------+
     |     [CELL ALPHA]      |                 |      [CELL BETA]      |
     |                       |                 |                       |
     | Orders Service (Pods) |                 | Orders Service (Pods) |
     | Kafka Consumer Group  |                 | Kafka Consumer Group  |
     | Shard Alpha DB (Pg)   |                 | Shard Beta DB (Pg)    |
     +-----------------------+                 +-----------------------+
     (Blast Radius: Max 50%)                   (Blast Radius: Max 50%)
```

---

## 2. Core Tenets of Cell Isolation

1. **Deterministic Blast Radius Containment**:
   - Each cell has a hard ceiling on the number of tenants or transactions it serves. If Cell Alpha experiences an unexpected crash or memory leak, **Cell Beta is 100% unaffected**.
2. **Zero Shared State Between Cells**:
   - Each cell maintains its own dedicated PostgreSQL shard (`orders_shard_alpha`, `orders_shard_beta`).
   - Consumer groups are scoped per cell (`orders-group-cell-alpha`, `orders-group-cell-beta`).
3. **Deterministic Routing via Edge Envoy / Istio**:
   - Ingress and API Gateway evaluate incoming requests:
     - Header `X-Cell-Id`: Directed explicitly to designated cell pods.
     - Fallback / Hashing: When no header is present, consistent hashing of Tenant ID or User ID assigns traffic deterministically.
4. **Autonomous Observability & Tracing**:
   - `CellContextFilter` injects `cell_id` into SLF4J `MDC` context.
   - Logs across Elasticsearch / Loki automatically carry `cell_id="cell-alpha"` or `cell_id="cell-beta"`.
   - Prometheus metrics record `ecommerce_cell_requests_total{cell_id="..."}`.

---

## 3. Kubernetes Multi-Cell Manifests

The cluster topology is maintained under `k8s/cells/`:

| Manifest | Purpose |
| :--- | :--- |
| [`k8s/cells/cell-alpha.yaml`](../../k8s/cells/cell-alpha.yaml) | Deployment & ClusterIP Service for Cell Alpha (`CELL_ID=cell-alpha`, Shard Alpha) |
| [`k8s/cells/cell-beta.yaml`](../../k8s/cells/cell-beta.yaml) | Deployment & ClusterIP Service for Cell Beta (`CELL_ID=cell-beta`, Shard Beta) |
| [`k8s/cells/cell-router.yaml`](../../k8s/cells/cell-router.yaml) | Istio `VirtualService` & `DestinationRule` performing content-based routing & circuit breaker ejection |

---

## 4. Emergency Cell Evacuation Procedure (Runbook)

If a hardware fault or unrecoverable state affects `cell-alpha`:

1. **Evacuate Traffic**:
   Update `k8s/cells/cell-router.yaml` to shift default weight from `50/50` to `100% cell-beta`:
   ```bash
   kubectl apply -f k8s/cells/cell-router-evacuate-alpha.yaml
   ```
2. **Quarantine Cell Alpha**:
   Scale Cell Alpha pods to 0 or isolate network namespace:
   ```bash
   kubectl scale deployment orders-service-cell-alpha --replicas=0 -n prod
   ```
3. **Drain & Remediate**:
   Run database shard consistency checks, apply hotfixes, and run chaos verification before reintroducing traffic.
