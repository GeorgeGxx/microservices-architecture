# 📊 Pillar 04: Observability & Telemetry

> [!TIP]
> 🧭 **[Enterprise Platform Hub](../../README.md)** > **04. Observability & Telemetry**

---

## 🎯 Domain Overview

The **Observability & Telemetry** pillar provides full-stack visibility across the microservices ecosystem using the **LGTM Stack** (Loki, Grafana, Tempo, Mimir/Prometheus) unified through **Grafana Alloy** and the **OpenTelemetry (OTel)** standard. It enables three-dimensional correlation: linking metrics anomalies to distributed trace spans and granular application logs.

```mermaid
flowchart TD
    subgraph Sources ["Telemetry Sources"]
        APPS["Microservices (Micrometer / Java 21)"]
        ROUTER["Cosmo Router (GraphQL Metrics)"]
        ISTIO["Istio Envoy (mTLS Mesh Access Logs)"]
    end

    subgraph Collection ["Collection & Processing"]
        ALLOY["Grafana Alloy (OTel Collector)"]
    end

    subgraph Storage ["LGTM Telemetry Backends"]
        PROM["Prometheus (Metrics • Port 9090)"]
        TEMPO["Grafana Tempo (Traces • Port 3200)"]
        LOKI["Grafana Loki (Logs • Port 3100)"]
    end

    subgraph Visualization ["Unified Visualization"]
        GRAFANA["Grafana Dashboards (Port 3000)<br/>• Business Operations Dashboard<br/>• Technical & Security Dashboard"]
    end

    APPS -->|OTLP gRPC| ALLOY
    ROUTER -->|Prometheus Scrape| ALLOY
    ISTIO -->|Access Logs| ALLOY

    ALLOY -->|Metrics| PROM
    ALLOY -->|Traces| TEMPO
    ALLOY -->|Logs| LOKI

    PROM --> GRAFANA
    TEMPO --> GRAFANA
    LOKI --> GRAFANA
```

---

## 📚 Document Index & Recommended Reading Order

| # | Document | Primary Persona | Strategic Scope & Key Takeaways |
| :-: | :--- | :--- | :--- |
| **1** | [**OBSERVABILITY_QUERIES.md**](./OBSERVABILITY_QUERIES.md) | SREs, DevOps, Developers | Comprehensive query handbook: PromQL (throughput, error rates, JVM heap, HikariCP), LogQL (structured JSON, log levels), TraceQL (distributed traces), and alert definitions. |

---

## 🧭 Platform Documentation Pillars

* 🏗️ **[Pillar 01: System Architecture & Technical Design](../01-architecture/README.md)**
* 🚀 **[Pillar 02: Platform Operations & Local Deployment](../02-operations/README.md)**
* 🛡️ **[Pillar 03: DevSecOps, Governance & Quality Assurance](../03-devsecops-and-testing/README.md)**
* 📊 **Pillar 04:** Observability & Telemetry (You are here)
