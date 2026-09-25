# 🏛️ Enterprise Microservices Architecture

<p align="center">
  <img src="https://img.shields.io/badge/Java-21-orange.svg?style=for-the-badge&logo=openjdk" alt="Java 21" />
  <img src="https://img.shields.io/badge/Spring%20Boot-4.0.8-brightgreen.svg?style=for-the-badge&logo=springboot" alt="Spring Boot 4.0.8" />
  <img src="https://img.shields.io/badge/Angular-21%20SPA-red.svg?style=for-the-badge&logo=angular" alt="Angular 21" />
  <img src="https://img.shields.io/badge/Keycloak-26.7.3-blue.svg?style=for-the-badge&logo=keycloak" alt="Keycloak 26" />
  <img src="https://img.shields.io/badge/Istio-Service%20Mesh-466BB0.svg?style=for-the-badge&logo=istio" alt="Istio" />
  <img src="https://img.shields.io/badge/HashiCorp-Vault-black.svg?style=for-the-badge&logo=vault" alt="Vault" />
  <img src="https://img.shields.io/badge/KEDA-v2.20.1-blueviolet.svg?style=for-the-badge&logo=kubernetes" alt="KEDA v2.20.1" />
  <img src="https://img.shields.io/badge/Grafana-LGTM%20Stack-F46800.svg?style=for-the-badge&logo=grafana" alt="Grafana LGTM" />
  <img src="https://img.shields.io/badge/DevSecOps-12--Stage%20Pipeline-success.svg?style=for-the-badge&logo=githubactions" alt="DevSecOps" />
  <img src="https://img.shields.io/badge/Newman%20Tests-22%2F22%20Passing-brightgreen.svg?style=for-the-badge&logo=postman" alt="Newman 22/22 Passing" />
</p>

> **Enterprise Multi-Cloud Microservices Platform** built with **Java 21**, **Spring Boot 4.0.8**, and **Angular 21**. Features automated **DHL tracking number generation**, real-time **Cart Abandonment Rate** telemetry, **Saga distributed transactions**, **Istio Service Mesh**, **HashiCorp Vault**, **Keycloak OAuth2/OIDC**, **KEDA v2.20.1 Event-Driven Autoscaling (Kafka Lag & Prometheus RPS)**, and full **DevSecOps automation** across AWS, Azure, GCP, and local Minikube.

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

## 📚 Specialized Documentation Hub

To keep this overview concise and practical, in-depth architectural specifications, cloud matrices, and operational manuals have been modularized into dedicated guides:

| Guide | Focus & Key Contents | Target Audience |
| :--- | :--- | :--- |
| [🏛️ **Architecture & Domain Guide**](./docs/ARCHITECTURE.md) | Domain-Driven Design (DDD), Saga compensation flow, Keycloak 26 IAM, HashiCorp Vault secrets, Angular 21 Signal store, POS QR workflows, and Amazon/Mercado Libre e-commerce models. | Software Architects, Developers |
| [☸️ **Local Deployment & Kubernetes**](./docs/LOCAL_DEPLOYMENT.md) | Docker Compose (15 services), Minikube cluster setup (6 CPUs / 12 GB RAM / 40 GB disk), Istio service mesh, Envoy sidecars, and cluster resiliency (HPA, ESO, Alertmanager). | DevOps, Platform Engineers |
| [🛡️ **DevSecOps Platform & CI/CD**](./docs/DEVSECOPS_AND_CI_CD.md) | 12-stage enterprise pipeline, Policy-as-Code (OPA / Gatekeeper), SAST (Semgrep, Gitleaks), Container scanning (Trivy), DAST (OWASP ZAP), and ArgoCD GitOps sync. | SecOps, Cloud Engineers |
| [📊 **Observability & Query Handbook**](./docs/OBSERVABILITY_QUERIES.md) | Comprehensive catalog and cheat sheet for PromQL (business funnels, RED signals, JVM), LogQL (Loki error hunting, trace correlation), and TraceQL (Tempo spans). | SRE, Operations Engineers |
| [🧪 **Testing, Simulation & Chaos**](./docs/TESTING_AND_CHAOS.md) | Unified simulation engine (`simulate.py`), automated smoke tests (`smoke.py`), DDoS botnet stress tests, stock exhaustion chaos drills, and Newman API contract testing. | QA Engineers, Developers |
| [☁️ **Multi-Cloud Terraform & Rollbacks**](./docs/MULTI_CLOUD_TERRAFORM.md) | Infrastructure as Code for AWS (EKS/RDS), Azure (AKS/Postgres), and GCP (GKE/CloudSQL), reusable Terraform modules, and automated 3-tier rollback mechanisms. | Cloud Architects, SRE |
| [🛠️ **Automation Scripts Reference**](./docs/SCRIPTS_REFERENCE.md) | Complete CLI reference for `platform.ps1`, cloud helpers (`manage-aws.ps1`, `manage-azure.ps1`, `manage-gcp.ps1`), FinOps disk cleanup, and build automation. | Platform Ops, SysAdmins |
| [📦 **Postman & Newman API Suite**](./devsecops/testing/newman/microservices.postman_collection.json) | Unified 22-request API collection with 1-click Keycloak public token (zero secrets), DHL generation, Cart Abandonment events, and dynamic `{{order_id}}` chaining. | API Developers, QA |

---

## 🔌 Service, Port & Credentials Matrix

| Service | Technology | Port | Access URL | Default Credentials |
| :--- | :--- | :---: | :--- | :--- |
| **Keycloak IAM** | Keycloak 26.7.3 (OIDC / OAuth2) | `8181` / `9000` | [http://localhost:8181](http://localhost:8181) | `admin` / `admin` |
| **Angular Frontend** | Angular 21 / Nginx | `4200` | [http://localhost:4200](http://localhost:4200) | `admin_user` / `admin` & `basic_user` / `password` |
| **API Gateway** | Spring Cloud Gateway 4.0.8 (Swagger UI) | `8080` | [http://localhost:8080/swagger-ui.html](http://localhost:8080/swagger-ui.html) | Bearer JWT (Keycloak) |
| **Products Service** | Spring Boot 4.0.8 | `8004` | [http://localhost:8080/api/product](http://localhost:8080/api/product) | Internal / Gateway Routed |
| **Orders Service** | Spring Boot 4.0.8 | `8003` | [http://localhost:8080/api/order](http://localhost:8080/api/order) | Internal / Gateway Routed |
| **Inventory Service** | Spring Boot 4.0.8 | `8001` | [http://localhost:8080/api/inventory](http://localhost:8080/api/inventory) | Internal / Gateway Routed |
| **Notification Service** | Spring Boot 4.0.8 | `8002` | [http://localhost:8080/api/notifications/stream](http://localhost:8080/api/notifications/stream) | SSE Stream |
| **Kafka Broker** | Apache Kafka (KRaft) 7.8.0 | `9092` / `9094` | `localhost:9092` / `localhost:9094` | SASL PLAIN *(Encrypted network)* |
| **Kafka Exporter** | Prometheus Kafka Exporter 1.9 | `9308` | [http://localhost:9308/metrics](http://localhost:9308/metrics) | *(No auth required)* |
| **Redis & Exporter** | Redis 8.8.1 / Exporter 1.82 | `6379` / `9121` | `localhost:6379` • [`:9121/metrics`](http://localhost:9121/metrics) | *(Password protected)* |
| **PostgreSQL DBs** | PostgreSQL 18 (DB-per-Service) | `5431`–`5435` | `localhost:5431, 5433, 5434, 5435` | `postgres` / `postgres` |
| **Postgres Exporter** | Prometheus Postgres Exporter 0.20 | `9187` | [http://localhost:9187/metrics](http://localhost:9187/metrics) | *(No auth required)* |
| **HashiCorp Vault** | Vault 2.0.4 (KV-v2 / Transit) | `8200` | [http://localhost:8200](http://localhost:8200) | Root Token: `root` |
| **OPA Gatekeeper** | Open Policy Agent Gatekeeper 3.23.1 | `8888` / `8443` | [http://localhost:8888](http://localhost:8888) | *(Admission Webhook / Metrics)* |
| **OpenTelemetry Collector** | OTel Collector Contrib 0.159 | `4317` / `4318` | `localhost:4317` (gRPC) • [`:4318`](http://localhost:4318) (HTTP) | *(OTLP Ingestion)* |
| **Grafana** | Grafana 13.2.1 | `3000` | [http://localhost:3000](http://localhost:3000) | `admin` / `admin` |
| **Prometheus** | Prometheus TSDB 3.14.0 | `9090` | [http://localhost:9090/targets](http://localhost:9090/targets) | *(No auth required)* |
| **Loki** | Grafana Loki 3.7.4 | `3100` | `localhost:3100` | *(Via Grafana datasource)* |
| **Tempo** | Grafana Tempo 3.0.3 | `3200` | `localhost:3200` | *(Via Grafana datasource)* |
| **Alloy** | Grafana Alloy 1.19.1 | `3300` | `localhost:3300` | *(Via Grafana datasource)* |
| **Istio Ingress Gateway** | Envoy Proxy (Istio 1.31.1) | `80` / `443` | [http://localhost](http://localhost) | Mesh Ingress |
| **Kiali Dashboard** | Kiali 2.31.0 | `20001` | [http://localhost:20001](http://localhost:20001) | *(No auth required)* |

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

## 🚀 Quick Start (Up in 3 Minutes)

### Option A: Local Docker Compose (15 Services)

The fastest way to spin up the complete ecosystem including all microservices, databases, Keycloak, Vault, and Grafana:

```powershell
# 1. Clone the repository
git clone https://github.com/georgegxx/microservices-architecture.git
cd microservices-architecture

# 2. Copy environment file if not already present and define the passwords
cp .example.env .env

# 3. Start Keycloak and its database in detached mode
docker compose up -d --build keycloak

# 4. Native PowerShell script (auto-syncs client secret into .env):
pwsh -File .\scripts\bootstrap-keycloak.ps1

# 5. Launch all 15 services in detached mode:
docker compose up -d --build

# 6. Verify healthy startup across all containers:
docker compose ps

# 7. Graceful shutdown & volume teardown
docker compose down -v
```

**Recommended local resources:** 6 CPU cores and 12 GB RAM free — the full Docker Compose stack runs ~20 containers (5 microservices, frontend, Keycloak, Postgres, Kafka, Redis, and the Grafana LGTM observability stack).

---

### Option B: Local Kubernetes on Minikube (Enterprise DevSecOps)

To deploy the entire production-grade stack on Minikube with **Istio Service Mesh**, **OPA Gatekeeper**, and **Helm**:

```powershell
# 1. Host CLI Audit & Automated Winget Installation
.\platform.ps1 tools

# 2. Start Minikube, initialize Istio Service Mesh, and deploy the umbrella Helm chart:
.\platform.ps1 up -Platform minikube -Environment dev -WithIstio

# 3. Audit platform health, pods, NodePorts, and Gatekeeper OPA policies:
.\platform.ps1 doctor -Platform minikube -Environment dev

# 4 Check all pods running
kubectl get pods -A
kubectl get pods -n dev # observability, auth, data, ..

# 5. Destroy the entire stack:
.\platform.ps1 down -Destroy
```

> 📘 **Step-by-step Minikube guide:** Detailed hardware allocation, network topologies, and DNS setup are available in [docs/LOCAL_DEPLOYMENT.md](./docs/LOCAL_DEPLOYMENT.md).
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

## 📁 Repository Structure

```text
microservices-architecture/
├── .github/workflows/              # GitHub Actions CI/CD (12-Stage Enterprise Pipelines)
├── api-gateway/                    # Spring Cloud Gateway (Port 8080 • Rate Limiting)
├── argocd                          # GitOps and CD Deployments
├── azure-devops                    # Azure DevOps Pipeline YAML files
├── devsecops/                      # Centralized DevSecOps Hub
│   ├── compliance/trivy/           # Trivy container scanner configuration
|   ├── dast/zap/                   # OWASP ZAP baseline rules and profiles
│   ├── policies/                   # OPA Rego Conftest & Gatekeeper constraints
│   ├── reference/aws-eks/          # GHA and ArgoCDfor AWS (Lab version)
|   ├── sast/gitleaks/              # Gitleaks and Semgrep static security configs
│   └── testing/newman/             # microservices.postman_collection.json (22-request API suite)
├── docs/                           # 📚 Specialized Modular Documentation
│   ├── ARCHITECTURE.md             # Tactical DDD, Sagas, Security, POS & E-Commerce
│   ├── LOCAL_DEPLOYMENT.md         # Docker Compose, Minikube, Istio & Resiliency
│   ├── DEVSECOPS_AND_CI_CD.md      # 12-Stage Pipeline, OPA, Trivy & Multi-CI/CD
│   ├── GIT_WORKFLOW_AND_COLLABORATION.md # Trunk-based / Gitflow, branch drift & rollback playbooks
│   ├── OBSERVABILITY_QUERIES.md    # PromQL, LogQL, and TraceQL Telemetry Handbook
│   ├── TESTING_AND_CHAOS.md        # Load simulation, DDoS, Chaos & Newman tests
│   ├── MULTI_CLOUD_TERRAFORM.md    # AWS, Azure, GCP Terraform & Rollback Guide
│   ├── SCRIPTS_REFERENCE.md        # Complete platform.ps1 & automation scripts manual
│   ├── Diagrams.drawio             # 12-Page Architectural Blueprint (Draw.io)
│   └── realm-export.json           # Keycloak 26 Realm configuration backup
├── frontend/                       # Angular 21 Reactive SPA (Nginx Distroless)
├── helm/                           # Kubernetes Helm Charts (Umbrella chart & subcharts)
├── inventory-service/              # Stock allocation & verification (Port 8001)
├── k8s/                            # Kubernetes manifests & Istio routing rules
├── notification-service/           # Kafka event consumer & SSE Stream (Port 8002)
├── observability/                  # Grafana LGTM provisioning (Dashboards, Alloy, Loki, Tempo)
├── orders-service/                 # Order orchestration & Saga orchestrator (Port 8003)
├── products-service/               # Product catalog domain (Port 8004)
├── scripts/                        # Enterprise automation scripts (PowerShell & Python)
│   ├── testing/                    # Specialized testing & load simulation (simulate, smoke, verify, check)
│   ├── bootstrap-keycloak.ps1      # Keycloak 26 IAM realm bootstrapper & client secret sync
│   ├── build-all.py                # Concurrent Java & Angular container image compiler
│   ├── endpoint-smoke-test.py      # Synthetic post-deployment health & SLO prober
│   ├── generate-secure-secrets.py  # CSPRNG cryptographic secret & JWT key generator
│   ├── generate_drawio.py          # Programmatic 12-page architectural diagram generator
│   ├── local-cost-estimator.py     # Air-gapped FinOps cloud cost & savings calculator
│   ├── supervise-tunnels.py        # Resilient background port-forward supervisor daemon
│   └── update_dashboards.py        # Grafana dashboard JSON generator & synchronizer
├── terraform/                      # Multi-Cloud IaC (AWS, Azure, GCP modules & workspaces)
├── .example.env                    # Example environment file
├── .gitattributes                  # Git attributes file
├── .gitignore                      # Git ignore file
├── .gitleaks.toml                  # Gitleaks configuration file
├── .gitleaksignore                 # Gitleaks ignore file
├── bitbucket-pipelines.yml         # Bitbucket Pipelines CI/CD configuration
├── compose.yaml                    # Local multi-service development stack (15 containers)
├── platform.ps1                    # Enterprise Platform Master CLI Orchestrator
├── pom.xml                         # Maven Multi-Module Reactor (Java 21, Spring Boot 4.0.8)
└── README.md                       # README file
```
---

## 📄 License

This project is licensed under the **MIT License** — see the [LICENSE](LICENSE) file for details.
