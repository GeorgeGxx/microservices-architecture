# 📄 ADR-007: Event-Driven Autoscaling with KEDA (Kubernetes Event-driven Autoscaling)

* **Status:** 🟢 ACCEPTED
* **Deciders:** Solution Architect, Tech Lead, SRE Lead
* **Date:** 2026-03-01
* **Technical Story:** Predictive & Reactive Event-Driven Autoscaling

---

## 🎯 Context & Problem Statement

Standard Kubernetes Horizontal Pod Autoscalers (HPA) rely strictly on CPU and Memory utilization metrics. In asynchronous event-driven microservices, queue backlog or sudden traffic spikes can saturate consumer processing long before CPU or Memory metrics breach autoscale thresholds, causing severe lag and violated delivery SLOs.

We require an autoscaler capable of:
1. Scaling consumer pods based directly on external event metrics (Kafka consumer group lag).
2. Scaling API services based on incoming HTTP request rates via Prometheus.
3. Scaling down to zero replicas during off-peak hours in non-production environments to minimize cloud spend.

---

## ⚖️ Decision Drivers

1. **Reactive Responsiveness:** React to queue lag instantly before messages accumulate.
2. **Multi-Source Metric Triggers:** Support Kafka, Prometheus, and Redis metrics natively.
3. **CNCF Standard:** Proven, vendor-neutral Kubernetes operator.
4. **Cost Optimization:** Capability to scale idle workloads down to zero.

---

## 🔍 Considered Alternatives

* **Option 1 (Baseline):** Default Kubernetes HPA (CPU / Memory only)
* **Option 2:** KEDA (Kubernetes Event-driven Autoscaling Operator)
* **Option 3:** Custom Prometheus Adapter with standard HPA

---

## 📊 Pugh Multi-Criteria Decision Matrix

| Evaluation Criteria | Weight (1-5) | Option 1: Standard CPU/RAM HPA | Option 2: KEDA Operator | Option 3: Custom Prometheus Adapter |
| :--- | :---: | :---: | :---: | :---: |
| **Kafka Lag Metric Trigger** | 5 | 0 (Baseline: unsupported) | **+1** (Native `kafka` scaler) | 0 (Requires complex PromQL) |
| **Zero-to-One Activation** | 4 | 0 (Baseline: minimum 1 replica) | **+1** (Scale to 0 supported) | -1 (Cannot scale from 0) |
| **Declarative Custom Resource (CRD)** | 4 | 0 (Baseline) | **+1** (Simple `ScaledObject`) | -1 (Complex adapter config) |
| **Ecosystem & Community Support** | 3 | 0 (Baseline) | **+1** (CNCF Graduated) | 0 (Community maintained) |
| **Weighted Total** | - | **0.00** | **+16 (WINNER)** | -5.00 |

---

## 💡 Decision Outcome

Chosen option: **Option 2 (KEDA)**.

### Positive Consequences
* **Lag-Based Scaling:** `notification-service` scales automatically from 1 to 5 replicas when the Kafka topic `orders-topic` consumer lag exceeds 10 messages.
* **Declarative Configuration:** Maintained via clean `ScaledObject` YAML manifests in the Helm chart.
* **SLO Protection:** Eliminates email/notification backlog during flash sales or traffic bursts.
