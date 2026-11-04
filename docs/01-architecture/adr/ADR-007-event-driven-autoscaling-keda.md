# ADR-007: Event-Driven Autoscaling with KEDA (Kubernetes Event-driven Autoscaling)

* **Status:** ACCEPTED
* **Deciders:** Solution Architect, Tech Lead, SRE Lead
* **Date:** 2026-03-01 (Updated: 2026-11-04)
* **Technical Story:** Predictive & Reactive Event-Driven Autoscaling Across Async & Sync Microservices

---

## Context & Problem Statement

Standard Kubernetes Horizontal Pod Autoscalers (HPA) rely strictly on CPU and Memory utilization metrics. In asynchronous event-driven microservices, queue backlog or sudden traffic spikes can saturate consumer processing long before CPU or Memory metrics breach autoscale thresholds, causing severe lag and violated delivery SLOs.

We require an autoscaler capable of:
1. Scaling consumer pods based directly on external event metrics (Kafka consumer group lag).
2. Scaling API services based on incoming HTTP request rates via Prometheus.
3. Managing unified `HorizontalPodAutoscaler` resources without duplicate controller race conditions or flapping.
4. Supporting predictive scaling across all core business microservices (`payments-service`, `fulfillment-service`, `analytics-service`, `orders-service`, `notification-service`, and `inventory-service`).

---

## Decision Drivers

1. **Reactive Responsiveness:** React to queue lag instantly before messages accumulate in Kafka topics.
2. **Multi-Source Metric Triggers:** Support Kafka lag, Prometheus queries, CPU, and memory metrics simultaneously.
3. **CNCF Standard:** Proven, vendor-neutral Kubernetes operator with native Custom Resource Definitions (`ScaledObject`).
4. **Collision Avoidance:** Exclusive ownership of `HorizontalPodAutoscaler` objects to avoid dual-scaling conflicts.

---

## Considered Alternatives

* **Option 1 (Baseline):** Default Kubernetes HPA (CPU / Memory only)
* **Option 2:** KEDA (Kubernetes Event-driven Autoscaling Operator)
* **Option 3:** Custom Prometheus Adapter with standard HPA

---

## Pugh Multi-Criteria Decision Matrix

| Evaluation Criteria | Weight (1-5) | Option 1: Standard CPU/RAM HPA | Option 2: KEDA Operator | Option 3: Custom Prometheus Adapter |
| :--- | :---: | :---: | :---: | :---: |
| **Kafka Lag Metric Trigger** | 5 | 0 (Baseline: unsupported) | **+1** (Native `kafka` scaler) | 0 (Requires complex PromQL) |
| **Zero-to-One Activation** | 4 | 0 (Baseline: minimum 1 replica) | **+1** (Scale to 0 supported) | -1 (Cannot scale from 0) |
| **Declarative Custom Resource (CRD)** | 4 | 0 (Baseline) | **+1** (Simple `ScaledObject`) | -1 (Complex adapter config) |
| **Ecosystem & Community Support** | 3 | 0 (Baseline) | **+1** (CNCF Graduated) | 0 (Community maintained) |
| **Weighted Total** | - | **0.00** | **+16 (WINNER)** | -5.00 |

---

## Decision Outcome

Chosen option: **Option 2 (KEDA)**.

### Implemented Autoscaling Topology & Trigger Matrix

All core business microservices define declarative `ScaledObject` resources (`helm/charts/*/templates/scaledobject.yaml`) with a scale boundary of 1 to 3 replicas:

| Microservice | ScaledObject Trigger 1 (Event-Driven) | ScaledObject Trigger 2 (Traffic / Resource) | Scale Boundaries |
| :--- | :--- | :--- | :--- |
| **`payments-service`** | **Kafka Consumer Lag**<br>Topic: `orders-topic`<br>Group: `payments-service-group`<br>Threshold: `10` messages | **CPU Utilization** (70%) & **Prometheus Request Rate** | `min: 1`, `max: 3` |
| **`fulfillment-service`** | **Kafka Consumer Lag**<br>Topic: `payments-topic`<br>Group: `fulfillment-service-group`<br>Threshold: `10` messages | **CPU Utilization** (70%) & **Prometheus Request Rate** | `min: 1`, `max: 3` |
| **`analytics-service`** | **Kafka Consumer Lag**<br>Topic: `orders-topic`<br>Group: `analytics-service-group`<br>Threshold: `10` messages | **Prometheus Request Rate** (`ecommerce_funnel_events_total` / `http_requests_total`, threshold: `80` req/s) & **CPU** (70%) | `min: 1`, `max: 3` |
| **`notification-service`** | **Kafka Consumer Lag**<br>Topic: `orders-topic`<br>Group: `notification-group`<br>Threshold: `10` messages | **CPU Utilization** (70%) | `min: 1`, `max: 3` |
| **`orders-service`** | **Prometheus Request Rate**<br>`http_server_requests_seconds_count` (threshold: `80` req/s) | **CPU Utilization** (70%) | `min: 1`, `max: 3` |
| **`inventory-service`** | **Prometheus Request Rate**<br>`http_server_requests_seconds_count` (threshold: `80` req/s) | **CPU Utilization** (70%) | `min: 1`, `max: 3` |

### Controller Protection & Mutual Exclusion

To prevent race conditions where both Kubernetes native `HorizontalPodAutoscaler` and KEDA attempt to scale the same Deployment, each chart's `templates/hpa.yaml` implements a mutual exclusion guard:
```yaml
{{- if and .Values.autoscaling.enabled (not (and .Values.keda .Values.keda.enabled)) }}
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
...
{{- end }}
```
When KEDA is enabled (`keda.enabled: true`), the KEDA controller automatically creates and manages `keda-hpa-<service>-scaler` as the sole scale authority. When KEDA is disabled, native HPA takes over seamlessly.
