# 📄 ADR-008: Full-Stack LGTM Telemetry Engine & OpenTelemetry Standardization

* **Status:** 🟢 ACCEPTED
* **Deciders:** Enterprise Architect, Observability Lead, SRE Lead, Tech Lead
* **Date:** 2026-03-08
* **Technical Story:** Cloud-Native Telemetry & Vendor-Neutral Observability

---

## 🎯 Context & Problem Statement

Proprietary Application Performance Monitoring (APM) tools (e.g. Datadog, New Relic, Dynatrace) impose exorbitant ingest/host pricing models, cause vendor lock-in through closed-source agents, and cannot be run locally on developer workstations without internet connectivity and paid licenses.

We require a unified, cloud-native telemetry stack that:
1. Standardizes all distributed trace propagation on OpenTelemetry (OTel / W3C TraceContext).
2. Unifies metrics, logs, and distributed traces into a single correlated pane of glass.
3. Operates identically on local Minikube developer clusters and enterprise multi-cloud environments.
4. Relies exclusively on open-source CNCF technologies.

---

## ⚖️ Decision Drivers

1. **Correlation Across Telemetry Signals:** Seamless jumping between PromQL metrics $\leftrightarrow$ LogQL logs $\leftrightarrow$ TraceQL spans.
2. **Zero Licensing Cost:** 100% open-source, deployable self-hosted or via open cloud standards.
3. **Local Developer Observability:** Developers must inspect traces and logs on `127.0.0.1:3000` during smoke and contract testing.
4. **Standardization:** OTel instrumentation in Go (Cosmo Router) and Java (Spring Boot subgraphs).

---

## 🔍 Considered Alternatives

* **Option 1 (Baseline):** Proprietary SaaS APM (Datadog / Dynatrace)
* **Option 2:** Open-Source LGTM Stack (Loki, Grafana, Tempo, Prometheus) + OpenTelemetry
* **Option 3:** ELK Stack (Elasticsearch, Logstash, Kibana) + Jaeger

---

## 📊 Pugh Multi-Criteria Decision Matrix

| Evaluation Criteria | Weight (1-5) | Option 1: SaaS APM (Datadog) | Option 2: LGTM Stack + OTel | Option 3: ELK Stack + Jaeger |
| :--- | :---: | :---: | :---: | :---: |
| **Cross-Signal Correlation (Metrics/Logs/Traces)** | 5 | 0 (Baseline) | **+1** (Grafana native correlation) | 0 (Fragmented Kibana/Jaeger) |
| **Zero License Cost & Multi-Cloud** | 5 | 0 (Baseline: high cost) | **+1** (100% open-source) | +1 (Open source / SSPL) |
| **Local Minikube Reproducibility** | 4 | 0 (Baseline: impossible) | **+1** (Runs locally in cluster) | -1 (Elasticsearch RAM heavy) |
| **OpenTelemetry Standard (OTLP)** | 4 | 0 (Baseline) | **+1** (Native OTLP receiver in Tempo) | 0 (Requires converters) |
| **Resource Footprint** | 3 | 0 (Baseline: low local agent) | **0** (Moderate in-cluster footprint) | -1 (Elasticsearch JVM heavy) |
| **Weighted Total** | - | **0.00** | **+18 (WINNER)** | +1.00 |

---

## 💡 Decision Outcome

Chosen option: **Option 2 (LGTM Stack + OpenTelemetry)**.

### Positive Consequences
* **Unified Observability:** Grafana (:3000) provides pre-configured dashboards correlating RED metrics, structured Loki logs, and Tempo distributed traces.
* **Distributed Tracing:** Every HTTP and GraphQL request carries W3C `traceparent` headers, visualizable in Grafana Tempo.
* **Telemetry Collection:** Grafana Alloy daemonset scrapes container logs and forwards OTLP signals automatically.
