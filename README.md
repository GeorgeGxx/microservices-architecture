# 🏛️ Enterprise Microservices Architecture

<p align="center">
  <img src="https://img.shields.io/badge/Java-21-orange.svg?style=for-the-badge&logo=openjdk" alt="Java 21" />
  <img src="https://img.shields.io/badge/Spring%20Boot-4.0.8-brightgreen.svg?style=for-the-badge&logo=springboot" alt="Spring Boot 4.0.8" />
  <img src="https://img.shields.io/badge/Angular-21%20SPA-red.svg?style=for-the-badge&logo=angular" alt="Angular 21" />
  <img src="https://img.shields.io/badge/Keycloak-26.7.3-blue.svg?style=for-the-badge&logo=keycloak" alt="Keycloak 26" />
  <img src="https://img.shields.io/badge/Istio-Service%20Mesh-466BB0.svg?style=for-the-badge&logo=istio" alt="Istio" />
  <img src="https://img.shields.io/badge/HashiCorp-Vault-black.svg?style=for-the-badge&logo=vault" alt="Vault" />
  <img src="https://img.shields.io/badge/Grafana-LGTM%20Stack-F46800.svg?style=for-the-badge&logo=grafana" alt="Grafana LGTM" />
  <img src="https://img.shields.io/badge/DevSecOps-12--Stage%20Pipeline-success.svg?style=for-the-badge&logo=githubactions" alt="DevSecOps" />
  <img src="https://img.shields.io/badge/Newman%20Tests-22%2F22%20Passing-brightgreen.svg?style=for-the-badge&logo=postman" alt="Newman 22/22 Passing" />
</p>

> **Enterprise Multi-Cloud Microservices Platform** built with **Java 21**, **Spring Boot 4.0.8**, and **Angular 21**. Features automated **DHL tracking number generation**, real-time **Cart Abandonment Rate** telemetry, **Saga distributed transactions**, **Istio Service Mesh**, **HashiCorp Vault**, **Keycloak OAuth2/OIDC**, and full **DevSecOps automation** across AWS, Azure, GCP, and local Minikube.

---

## 📚 Specialized Documentation Hub

To keep this overview concise and practical, in-depth architectural specifications, cloud matrices, and operational manuals have been modularized into dedicated guides:

| Guide | Focus & Key Contents | Target Audience |
| :--- | :--- | :--- |
| [🏛️ **Architecture & Domain Guide**](./docs/ARCHITECTURE.md) | Domain-Driven Design (DDD), Saga compensation flow, Keycloak 26 IAM, HashiCorp Vault secrets, Angular 21 Signal store, POS QR workflows, and Amazon/Mercado Libre e-commerce models. | Software Architects, Developers |
| [☸️ **Local Deployment & Kubernetes**](./docs/LOCAL_DEPLOYMENT.md) | Docker Compose (15 services), Minikube cluster setup (12 GB RAM / 80 GB disk), Istio service mesh, Envoy sidecars, and cluster resiliency (HPA, ESO, Alertmanager). | DevOps, Platform Engineers |
| [🛡️ **DevSecOps Platform & CI/CD**](./docs/DEVSECOPS_AND_CI_CD.md) | 12-stage enterprise pipeline, Policy-as-Code (OPA / Gatekeeper), SAST (Semgrep, Gitleaks), Container scanning (Trivy), DAST (OWASP ZAP), and ArgoCD GitOps sync. | SecOps, Cloud Engineers |
| [📊 **Observability & Query Handbook**](./docs/OBSERVABILITY_QUERIES.md) | Comprehensive catalog and cheat sheet for PromQL (business funnels, RED signals, JVM), LogQL (Loki error hunting, trace correlation), and TraceQL (Tempo spans). | SRE, Operations Engineers |
| [🧪 **Testing, Simulation & Chaos**](./docs/TESTING_AND_CHAOS.md) | Unified simulation engine (`simulate.py`), automated smoke tests (`smoke.py`), DDoS botnet stress tests, stock exhaustion chaos drills, and Newman API contract testing. | QA Engineers, Developers |
| [☁️ **Multi-Cloud Terraform & Rollbacks**](./docs/MULTI_CLOUD_TERRAFORM.md) | Infrastructure as Code for AWS (EKS/RDS), Azure (AKS/Postgres), and GCP (GKE/CloudSQL), reusable Terraform modules, and automated 3-tier rollback mechanisms. | Cloud Architects, SRE |
| [🛠️ **Automation Scripts Reference**](./docs/SCRIPTS_REFERENCE.md) | Complete CLI reference for `platform.ps1`, cloud helpers (`manage-aws.ps1`, `manage-azure.ps1`, `manage-gcp.ps1`), FinOps disk cleanup, and build automation. | Platform Ops, SysAdmins |
| [📦 **Postman & Newman API Suite**](./devsecops/testing/newman/microservices.postman_collection.json) | Unified 22-request API collection with 1-click Keycloak public token (zero secrets), DHL generation, Cart Abandonment events, and dynamic `{{order_id}}` chaining. | API Developers, QA |

---

## 🏛️ Master Architecture Diagram

```mermaid
graph TB
    subgraph Clients["🌐 Client Layer"]
        SPA["Angular 21 Reactive SPA<br/>(Signals • @defer • Port 4200)"]
        CLI["Platform CLI & Newman<br/>(platform.ps1 • newman run)"]
        EXT["External Webhooks / Mobile<br/>(POS Scanner • Cloudflare)"]
    end

    subgraph Security["🔐 Identity & Secrets"]
        KC["Keycloak 26.7.3<br/>(OIDC • PKCE • Port 8181)"]
        VAULT["HashiCorp Vault<br/>(KV-v2 • Transit • Port 8200)"]
    end

    subgraph Gateway["🚪 Ingress & API Gateway"]
        SCG["Spring Cloud Gateway<br/>(Port 8080 • Redis RateLimiter)"]
        ISTIO["Istio Ingress Gateway<br/>(Envoy • mTLS • Canary 90/10)"]
    end

    subgraph Microservices["⚙️ Core Domain Microservices (Spring Boot 4.0.8)"]
        PROD["Products Service<br/>(:8004 • MongoDB 7)"]
        ORD["Orders Service<br/>(:8003 • PostgreSQL 16 • Saga)"]
        INV["Inventory Service<br/>(:8001 • PostgreSQL 16)"]
        NOTIF["Notification Service<br/>(:8002 • SSE Realtime Stream)"]
    end

    subgraph EventBus["📨 Event Streaming & Caching"]
        KAFKA["Apache Kafka 3.9<br/>(KRaft • Port 9092)"]
        REDIS["Redis 7.4<br/>(Cache & Token-Bucket RateLimiter)"]
    end

    subgraph Observability["📊 Full-Stack Observability (LGTM Stack)"]
        PROM["Prometheus (:9090)<br/>(Micrometer 2.2.1 • PromQL)"]
        LOKI["Grafana Loki (:3100)<br/>(Centralized Logs • LogQL)"]
        TEMPO["Grafana Tempo (:3200)<br/>(Distributed Traces • TraceQL)"]
        GRAFANA["Grafana 13.2.1 (:3000)<br/>(Executive BI & SRE Dashboards)"]
    end

    SPA -->|Public OIDC Token| KC
    SPA -->|HTTP / REST| SCG
    CLI --> SCG
    EXT --> SCG
    SCG --> ISTIO

    ISTIO --> PROD
    ISTIO --> ORD
    ISTIO --> INV
    ISTIO --> NOTIF

    ORD -->|Stock Verification| INV
    ORD -->|Publish Order Events| KAFKA
    KAFKA -->|Consume & SSE Push| NOTIF

    PROD -.->|Fetch Secrets| VAULT
    ORD -.->|Fetch Secrets| VAULT
    INV -.->|Fetch Secrets| VAULT

    SCG -.->|Rate Limiting| REDIS
    PROD -.->|Cache Aside| REDIS

    Microservices -.->|Metrics| PROM
    Microservices -.->|Logs via Alloy| LOKI
    Microservices -.->|OTLP Spans| TEMPO
    GRAFANA --> PROM
    GRAFANA --> LOKI
    GRAFANA --> TEMPO
```

---

## 🚀 Quick Start (Up in 3 Minutes)

### Option A: Local Docker Compose (15 Services)

The fastest way to spin up the complete ecosystem including all microservices, databases, Keycloak, Vault, and Grafana:

```powershell
# 1. Clone the repository
git clone https://github.com/georgegxx/microservices-architecture.git
cd microservices-architecture

# 2. Launch all 15 services in detached mode:
docker compose up -d

# 3. Verify healthy startup across all containers:
docker compose ps
```

* 🌐 **Angular Storefront:** [http://localhost:4200](http://localhost:4200)
* 🚪 **API Gateway:** [http://localhost:8080](http://localhost:8080)
* 📊 **Grafana Observability:** [http://localhost:3000](http://localhost:3000) (Login: `admin` / `admin`)
* 🔐 **Keycloak Admin Console:** [http://localhost:8181](http://localhost:8181) (Login: `admin` / `admin`)

---

### Option B: Local Kubernetes on Minikube (Enterprise DevSecOps)

To deploy the entire production-grade stack on Minikube with **Istio Service Mesh**, **OPA Gatekeeper**, and **Helm**:

```powershell
# 1. Start Minikube and deploy the complete umbrella Helm chart:
.\scripts\minikube\deploy-minikube.ps1

# 2. Open tunnel access to all services:
.\scripts\minikube\tunnel-services.ps1
```

> 📘 **Step-by-step Minikube guide:** Detailed hardware allocation, network topologies, and DNS setup are available in [docs/LOCAL_DEPLOYMENT.md](./docs/LOCAL_DEPLOYMENT.md).

---

## 🔌 Service, Port & Credentials Matrix

| Service | Technology | Port | Access URL | Default Credentials |
| :--- | :--- | :---: | :--- | :--- |
| **Angular Frontend** | Angular 21 / Nginx | `4200` | [http://localhost:4200](http://localhost:4200) | `admin_user` / `admin` |
| **API Gateway** | Spring Cloud Gateway | `8080` | [http://localhost:8080](http://localhost:8080) | Bearer JWT (Keycloak) |
| **Products Service** | Spring Boot 4.0.8 | `8004` | [http://localhost:8080/api/product](http://localhost:8080/api/product) | Internal / Gateway Routed |
| **Orders Service** | Spring Boot 4.0.8 | `8003` | [http://localhost:8080/api/order](http://localhost:8080/api/order) | Internal / Gateway Routed |
| **Inventory Service** | Spring Boot 4.0.8 | `8001` | [http://localhost:8080/api/inventory](http://localhost:8080/api/inventory) | Internal / Gateway Routed |
| **Notification Service** | Spring Boot 4.0.8 | `8002` | [http://localhost:8080/api/notifications/stream](http://localhost:8080/api/notifications/stream) | SSE Stream |
| **Keycloak IAM** | Keycloak 26.7.3 | `8181` | [http://localhost:8181](http://localhost:8181) | `admin` / `admin` |
| **HashiCorp Vault** | Vault KV-v2 / Transit | `8200` | [http://localhost:8200](http://localhost:8200) | Root Token: `root` |
| **Grafana** | Grafana 13.2.1 | `3000` | [http://localhost:3000](http://localhost:3000) | `admin` / `admin` |
| **Prometheus** | Prometheus TSDB | `9090` | [http://localhost:9090](http://localhost:9090) | *(No auth required)* |
| **Loki Logs** | Grafana Loki | `3100` | [http://localhost:3100](http://localhost:3100) | *(Via Grafana datasource)* |
| **Tempo Traces** | Grafana Tempo | `3200` | [http://localhost:3200](http://localhost:3200) | *(Via Grafana datasource)* |
| **PostgreSQL** | PostgreSQL 16 | `5432` | `localhost:5432` | `postgres` / `postgres` |
| **MongoDB** | MongoDB 7.0 | `27017` | `localhost:27017` | `admin` / `password` |
| **Kafka Broker** | Apache Kafka (KRaft) | `9092` | `localhost:9092` | *(Internal network)* |
| **Redis** | Redis 7.4 | `6379` | `localhost:6379` | *(No password by default)* |

---

## ⚡ Core Enterprise Capabilities

### 🛒 E-Commerce & Retail Innovation
* **Automated DHL Tracking Generation:** Every successfully placed order automatically generates a trackable carrier tracking number (e.g. `DHL-A8B9C0D1`) and initial tracking event history.
* **Cart Abandonment Rate Telemetry:** Asynchronous funnel telemetry (`CART_ADD` $\rightarrow$ `CHECKOUT_START` $\rightarrow$ `CHECKOUT_STEP` $\rightarrow$ `PLACED`) published to Kafka, feeding live Prometheus gauges and Grafana BI conversion funnels.
* **Point of Sale (POS) & QR Scanner:** Dual workflow supporting standard checkout and physical POS cashier operations with Code-128 barcode scanning and instant SAT/CFDI invoice QR generation.

### 🔄 Distributed Reliability & Consistency
* **Saga Orchestration Pattern:** Graceful compensation and stock rollback when downstream payment or inventory allocation fails.
* **Distributed Idempotency:** Guaranteed once-only order processing via mandatory UUIDv4 `X-Idempotency-Key` headers backed by Redis deduplication.
* **Resilience4j Circuit Breakers:** Protects upstream callers with automatic state transitions (`CLOSED` $\rightarrow$ `OPEN` $\rightarrow$ `HALF_OPEN`) and thread-isolated bulkheads.

### 🛡️ Zero-Trust Security & DevSecOps
* **1-Click Authentication:** Public Keycloak client (`microservices_frontend`) with PKCE and zero `client_secret` requirements for developer workstations and mobile apps.
* **Centralized Secrets with HashiCorp Vault:** Dynamic secret generation and encryption-as-a-service (Transit Engine) replacing static environment variables.
* **Policy-as-Code (OPA & Gatekeeper):** Automated admission controller rules blocking privileged containers, enforced CPU/memory limits, and mandatory labels.

### 📊 Full-Stack Observability (LGTM Stack)
* **Pre-Provisioned Grafana Dashboards:**
  1. `🏢 Business Intelligence & Inventory Operations` (Net revenue, completed orders, AOV, Cart Abandonment Rate, SKU demand, cohort retention).
  2. `🛡️ Technical, Infrastructure & Security Operations (SRE)` (Golden signals, P95 latency, circuit breaker states, HikariCP pools, JVM Heap, threat level).
* **Deep Telemetry Correlation:** One-click drill-down in Grafana Explore linking Tempo distributed spans $\leftrightarrow$ Loki structured logs $\leftrightarrow$ Prometheus metrics.

---

## 📁 Repository Structure

```text
microservices-architecture/
├── .github/workflows/              # GitHub Actions CI/CD (12-Stage Enterprise Pipelines)
├── api-gateway/                    # Spring Cloud Gateway (Port 8080 • Rate Limiting)
├── devsecops/                      # Centralized DevSecOps Hub
│   ├── dast/zap/                   # OWASP ZAP baseline rules and profiles
│   ├── policies/                   # OPA Rego Conftest & Gatekeeper constraints
│   ├── sast/                       # Gitleaks and Semgrep static security configs
│   ├── compliance/trivy/           # Trivy container scanner configuration
│   └── testing/newman/             # microservices.postman_collection.json (22-request API suite)
├── docs/                           # 📚 Specialized Modular Documentation
│   ├── ARCHITECTURE.md             # Tactical DDD, Sagas, Security, POS & E-Commerce
│   ├── LOCAL_DEPLOYMENT.md         # Docker Compose, Minikube, Istio & Resiliency
│   ├── DEVSECOPS_AND_CI_CD.md      # 12-Stage Pipeline, OPA, Trivy & Multi-CI/CD
│   ├── OBSERVABILITY_QUERIES.md    # PromQL, LogQL, and TraceQL Telemetry Handbook
│   ├── TESTING_AND_CHAOS.md        # Load simulation, DDoS, Chaos & Newman tests
│   ├── MULTI_CLOUD_TERRAFORM.md    # AWS, Azure, GCP Terraform & Rollback Guide
│   ├── SCRIPTS_REFERENCE.md        # Complete platform.ps1 & automation scripts manual
│   ├── Diagrams.drawio             # 12-Page Architectural Blueprint (Draw.io)
│   └── realm-export.json           # Keycloak 26 Realm configuration backup
├── frontend/                       # Angular 21 Reactive SPA (Nginx Distroless)
├── inventory-service/              # Stock allocation & verification (Port 8001)
├── notification-service/           # Kafka event consumer & SSE Stream (Port 8002)
├── orders-service/                 # Order orchestration & Saga orchestrator (Port 8003)
├── products-service/               # Product catalog domain (Port 8004)
├── helm/                           # Kubernetes Helm Charts (Umbrella chart & subcharts)
├── k8s/                            # Kubernetes manifests & Istio routing rules
├── observability/                  # Grafana LGTM provisioning (Dashboards, Alloy, Loki, Tempo)
├── scripts/                        # Enterprise automation scripts (PowerShell & Python)
├── terraform/                      # Multi-Cloud IaC (AWS, Azure, GCP modules & workspaces)
├── compose.yaml                    # Local multi-service development stack (15 containers)
└── pom.xml                         # Maven Multi-Module Reactor (Java 21, Spring Boot 4.0.8)
```

---

## 🧪 Quick Test Run (Newman API Contract Suite)

Validate the entire 22-request API suite against the running cluster in 3 seconds:

```powershell
npx --yes newman run devsecops/testing/newman/microservices.postman_collection.json `
  --env-var "BASE_URL=http://localhost:8080" `
  --env-var "keycloak_url=http://localhost:8181" `
  --reporters cli
```

**Result:** 22/22 requests passing with 0 failures (`HTTP 200`, `201`, `202`).

---

## 📄 License

This project is licensed under the **MIT License** — see the [LICENSE](LICENSE) file for details.
