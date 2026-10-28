# 🏛️ Enterprise DevSecOps Governance & Operating Model

> [!TIP]
> 🧭 **[Enterprise Platform Hub](../../README.md)** > **03. DevSecOps & Testing** > `DEVSECOPS_GOVERNANCE_AND_MODEL.md`

---

## 🎯 Executive Overview

This document formalizes the **Enterprise DevSecOps Operating Model & Governance Framework** for the Microservices Architecture platform. It translates strategic business requirements into secure, resilient, and observable cloud-native services by bridging the gap between:

1. **Strategic & Business Governance** (Product Management, PMO, Enterprise Architecture)
2. **Shift-Left Engineering** (Development Teams, Technical Leads, Secure Code Quality)
3. **Automated Continuous Assurance** (CI/CD Pipelines, SAST, DAST, IaC, Contract & Performance Gates)
4. **Resilient Production Operations** (Platform/SRE, Observability, Incident Management, ServiceNow)

```mermaid
flowchart LR
    A["1. Strategy & Portfolio<br/>(WSJF, ROI, MVP)"] --> B["2. Arch & Threat Modeling<br/>(STRIDE, Schema-First, IaC)"]
    B --> C["3. Agile Construction<br/>(TDD, Pre-commit, PR Gates)"]
    C --> D["4. Automated Assurance<br/>(SAST, DAST, Newman, k6)"]
    D --> E["5. GitOps & Release<br/>(ArgoCD, Istio Canary, Helm)"]
    E --> F["6. Observability & SRE<br/>(SLOs, LGTM Stack, Feedback)"]
    F -.->|"Closed-Loop Feedback"| A
```

---

## 📐 Unified DevSecOps & S-SDLC Lifecycle Workflow

This workflow evolves traditional SDLC phases (such as manual design review boards, isolated testing blocks, and committee sign-off gates) into a **continuous, policy-driven Shift-Left and Shift-Right engineering pipeline** fully integrated into the microservices architecture.

### 👥 Six Multi-Disciplinary Stakeholder Personas
The operating model coordinates six distinct cross-functional roles across the entire platform lifecycle:

* 🔵 **Business / Product Owner (PO):** Defines value streams, functional acceptance criteria (Given-When-Then), releases authorization, and sprint priority.
* 🟢 **Team Leads / Solution Architecture:** Governs Architecture Decision Records (ADRs), non-functional requirements (NFRs), schema design, and code quality benchmarks.
* 🔴 **Developers:** Implements Test-Driven Development (TDD), clean code, pre-commit hygiene, atomic feature branches, and declarative schema evolution (JPA/Hibernate).
* 🟡 **Cybersecurity / SecOps:** Conducts threat modeling (STRIDE / abuse cases), enforces security quality gates, manages CVE triage, and audits runtime security posture.
* 🟠 **Testers / QA Automation:** Engineers automated API contract tests (Newman), integration suites, and resilience/load benchmarks (k6).
* 🔘 **Infrastructure / DevOps / SRE:** Provisions immutable IaC (Terraform), Helm charts, GitOps delivery (ArgoCD), service mesh (Istio), and telemetry collection (OTel, Grafana Alloy, Prometheus, Loki, Tempo).

### 🚀 Evolution from Traditional Committee Gates to Continuous Quality Gates

| Traditional Workflow Characteristic | DevSecOps & S-SDLC Evolution in Microservices Architecture | Implementation / Gate in Project |
| :--- | :--- | :--- |
| **Manual Committee Review 1 (Pre-Build)** | Replaced by **Definition of Ready (DoR)** with schema-first validation and peer-approved ADRs for breaking changes. | [QUALITY_GATES_AND_DOD.md](./QUALITY_GATES_AND_DOD.md) (DoR checklist) |
| **Vague "Tools Review" at end of Code** | Decomposed into continuous **Shift-Left automated gates** at Pre-commit (Gitleaks) and Pull Request (JaCoCo ≥ 80%, SonarQube SAST, Trivy SCA, secrets and IaC configuration). | [`.github/workflows/_service-ci-cd-template.yml`](../../.github/workflows/_service-ci-cd-template.yml) & [DoD Level 1](./QUALITY_GATES_AND_DOD.md) |
| **Manual Committee Review 2 (Pre-Testing)** | Replaced by **Automated Pull Request Validation & Branch Protection Rules** for merge into `develop`. | GitHub Actions branch protection & mandatory peer approval |
| **Isolated "Automation Stress Security" block** | Integrated into continuous **DoD Level 2 Staging Gate** via ArgoCD: Postman/Newman contract verification, Cosmo Router federation checks, k6 load testing, and OWASP ZAP DAST. | [`devsecops/testing/`](../../devsecops/testing/) & [`devsecops/dast/zap/`](../../devsecops/dast/zap/) |
| **IaC as a static deployment overlay** | **Declarative GitOps & Admission Control:** Terraform in `terraform/`, Helm in `helm/`, ArgoCD in `argocd/`, validated statically with Conftest/Rego and dynamically with OPA Gatekeeper. | [`devsecops/policies/`](../../devsecops/policies/) & [`argocd/`](../../argocd/) |
| **Manual Production CAB** | Replaced by **Progressive Canary Rollouts (Istio 10% → 100%)** with automated health checks, error-budget guardrails, and instant rollback. | Istio VirtualService + Prometheus SLO alert gates |
| **Linear "Fix & Refactor"** | **Closed-Loop Feedback:** Telemetry in Grafana Tempo (distributed traces), Loki (logs), and Prometheus (metrics) automatically correlates errors into RCA post-mortems and regression tests. | [OBSERVABILITY_QUERIES.md](../04-observability/OBSERVABILITY_QUERIES.md) |

### 🔄 End-to-End DevSecOps & S-SDLC Lifecycle Diagram

```mermaid
flowchart TD
    classDef biz fill:#e1f5fe,stroke:#0288d1,stroke-width:2px;
    classDef lead fill:#e8f8f5,stroke:#26a69a,stroke-width:2px;
    classDef dev fill:#ffebee,stroke:#e53935,stroke-width:2px;
    classDef sec fill:#fffde7,stroke:#fbc02d,stroke-width:2px;
    classDef qa fill:#fff3e0,stroke:#fb8c00,stroke-width:2px;
    classDef ops fill:#eceff1,stroke:#546e7a,stroke-width:2px;
    classDef gate fill:#ede7f6,stroke:#5e35b1,stroke-width:2px,stroke-dasharray: 5 5;

    subgraph Phase1 ["1. Strategic Conception & Threat Modeling (Shift-Left)"]
        US["📋 User Story & Value Stream<br/>• Business Value & Functional Criteria<br/>• Evil User Stories & Abuse Cases"]:::biz
        TD["📐 Technical Design & Architecture<br/>• Schema-First (GraphQL / Async Events)<br/>• Non-destructive DB Plan (Expand/Contract)<br/>• Threat Modeling (STRIDE / PASTA)"]:::lead
        TC["🧪 Contract & BDD Test Cases<br/>• Gherkin / Acceptance Test Suites<br/>• API Consumer Contracts"]:::qa
        DoR(["🚦 Automated DoR Quality Gate<br/>• Pre-validated Schema & ADR Approved<br/>• Zero breaking contract drift"]):::gate
        
        US --> TD
        TD <--> TC
        TD --> DoR
        DoR -.->|"Alternative Flows / Scope Rework"| US
    end

    subgraph Phase2 ["2. Secure Agile Construction & Component Gates"]
        TDD["💻 Test-Driven Development (TDD)<br/>• Unit tests written first<br/>• Clean Architecture & SOLID standards"]:::dev
        CODE["🔨 Implementation & Pre-commit<br/>• Local linting & formatting<br/>• Gitleaks secret detection hook"]:::dev
        PR["👥 Peer Review & Pull Request<br/>• Code review by Tech Leads<br/>• Conventional Commits verification"]:::lead
        DoD1(["🛡️ DoD Level 1 Gate (Automated CI)<br/>• Maven/TypeScript Compile (Zero warnings)<br/>• Unit & JaCoCo Coverage &ge; 80%<br/>• SAST (SonarQube) & SCA (Trivy CVEs)<br/>• IaC Misconfiguration (Trivy) & Policy (Conftest Rego)"]):::gate
        BUILD["📦 Immutable Container Build<br/>• 100% Non-root distroless (Java Debian & Chainguard Nginx)<br/>• Trivy image scan & Cosign signature"]:::ops

        DoR -->|Ready for Sprint| TDD
        TDD --> CODE
        CODE --> PR
        PR --> DoD1
        DoD1 -->|"Automated Gate Pass"| BUILD
        DoD1 -.->|"Fix & Refactor Loop"| CODE
    end

    subgraph Phase3 ["3. Staging Dynamic Validation & Integration Gates"]
        GITOPS_DEV["🔄 GitOps Sync to Staging<br/>• ArgoCD automated deployment<br/>• Ephemeral staging cluster sync"]:::ops
        DYNAMIC_TESTS["⚡ Dynamic Assurance Suite<br/>• API Contract Tests (Postman / Newman)<br/>• Cosmo Router Federated Composition<br/>• Resilience & Stress Load Testing (k6)<br/>• DAST Security Vulnerability Scan (OWASP ZAP)"]:::qa
        UAT["👔 Business UAT & Acceptance<br/>• End-to-end user workflow sign-off"]:::biz
        DoD2(["🟡 DoD Level 2 Gate (Integration Pass)<br/>• 23/23 Newman contract tests<br/>• Zero High/Critical OWASP ZAP alerts<br/>• k6 p95 &lt; 2000ms & error rate &lt; 2%"]):::gate

        BUILD --> GITOPS_DEV
        GITOPS_DEV --> DYNAMIC_TESTS
        DYNAMIC_TESTS --> DoD2
        DoD2 -->|Healthy Verification| UAT
        DYNAMIC_TESTS -.->|"Replicate & Fix Loop"| TDD
    end

    subgraph Phase4 ["4. Progressive Production Delivery & Policy Gates"]
        GITOPS_PROD["🚀 GitOps Release to Production<br/>• ArgoCD sync with Git tag vX.Y.Z<br/>• OPA Gatekeeper Admission Controller"]:::ops
        CANARY["🔀 Progressive Canary Traffic Shift<br/>• Istio Service Mesh (10% -> 50% -> 100%)<br/>• Automated SLO error budget monitoring"]:::ops
        PROD_LIVE["🌐 Live Multi-Cloud Cluster<br/>• Zero-Trust mTLS encryption<br/>• Keycloak JWT & Sealed Secrets/Vault"]:::ops
        DoD3(["🔴 DoD Level 3 Gate (Production Verification)<br/>• Zero SLO regression during Canary<br/>• Verified automated rollback plan"]):::gate

        UAT --> GITOPS_PROD
        GITOPS_PROD --> DoD3
        DoD3 --> CANARY
        CANARY --> PROD_LIVE
        DoD3 -.->|"Emergency Auto-Rollback"| GITOPS_PROD
    end

    subgraph Phase5 ["5. Observability, Resiliencia & Closed-Loop Feedback"]
        OBS["📊 Full-Stack LGTM Telemetry<br/>• Grafana Tempo (Distributed TraceQL)<br/>• Grafana Loki (Centralized LogQL)<br/>• Prometheus (Golden Signals & PromQL)"]:::ops
        RUNTIME_SEC["🛡️ Runtime Security & Audit<br/>• Anomaly triggers & SIEM monitoring"]:::sec
        POSTMORTEM["🔍 RCA & Blameless Post-Mortem<br/>• ServiceNow / Incident bridge<br/>• Automated regression test creation"]:::lead
        BACKLOG["📋 Backlog Prioritization & Technical Debt<br/>• Preventive security & hardening stories"]:::biz

        PROD_LIVE --> OBS
        PROD_LIVE --> RUNTIME_SEC
        OBS --> POSTMORTEM
        RUNTIME_SEC --> POSTMORTEM
        POSTMORTEM -.->|"Regression Test Added to Newman / k6"| TC
        POSTMORTEM -.->|"Preventive Debt / Threat Fix"| BACKLOG
        BACKLOG -.->|"Next Sprint Refinement"| US
    end
```

---

## 🔄 The 5-Phase End-to-End Delivery Lifecycle

```mermaid
sequenceDiagram
    autonumber
    actor Biz as Business / PO (🔵)
    actor Arch as Enterprise & Solution Arch (🟢)
    actor Sec as Cybersecurity Lead (🟡)
    actor Dev as Dev Team & Tech Lead (🔴)
    actor CI as CI/CD Pipeline (Automated ⚙️)
    actor Ops as SRE / Platform / Observability (🔘)
    actor ITSM as ServiceNow / Incident Mgmt

    rect rgb(240, 248, 255)
    Note over Biz,Arch: Phase 1: Portfolio & Architecture Conception
    Biz->>Arch: Business Need & Value Stream Hypothesis
    Arch->>Sec: Baseline Solution Architecture & Tech Feasibility
    Sec->>Arch: Threat Modeling (STRIDE) & Abuse Cases
    Arch->>Biz: Architecture Decision Record (ADR) + Approved MVP Scope
    end

    rect rgb(255, 250, 240)
    Note over Biz,Dev: Phase 2: Agile Refinement & Construction
    Biz->>Dev: Refined User Stories & Acceptance Criteria
    Dev->>Dev: TDD, Clean Code, Local Linting (Pre-commit)
    Dev->>Dev: Non-destructive DB Schema Evolution & IaC (Terraform)
    Dev->>Dev: Open Pull Request to 'develop'
    end

    rect rgb(240, 255, 240)
    Note over Dev,CI: Phase 3: Automated Quality & Security Gates
    CI->>CI: 1. Unit Tests & JaCoCo Coverage (≥ 80%)
    CI->>CI: 2. SAST (SonarQube Quality Gate)
    CI->>CI: 3. SCA & Secret Scan (Trivy & Gitleaks)
    CI->>CI: 4. IaC Configuration and Policy Check (Trivy / OPA)
    CI-->>Dev: Build Artifacts & Container Images
    end

    rect rgb(255, 245, 245)
    Note over CI,Ops: Phase 4: Staging Validation & Promotion
    CI->>Ops: Deploy to Staging (Helm / ArgoCD)
    CI->>CI: 5. Newman API Contract Check (23/23 Pass)
    CI->>CI: 6. k6 Load & SLO Benchmark (p95 < 200ms)
    CI->>CI: 7. OWASP ZAP Baseline DAST
    CI->>Ops: Promote to Production (Istio Canary 10% ➔ 100%)
    end

    rect rgb(245, 240, 255)
    Note over Ops,ITSM: Phase 5: Continuous Reliability & Feedback Loop
    Ops->>Ops: Distributed Tracing (Grafana Tempo) & Metrics (Prometheus/Grafana)
    Ops->>ITSM: Anomaly Trigger / PagerAlert
    ITSM->>Dev: P1/P2 Incident Root-Cause Analysis (Blameless Post-Mortem)
    Dev->>Biz: Preventive Technical Debt Stories added to Backlog
    end
```

---

## 📊 Comprehensive DevSecOps RACI Matrix

The following RACI matrix specifies organizational accountability across the multi-cloud platform:
- **R (Responsible):** The role that executes the task.
- **A (Accountable):** The individual with final approval and veto authority (only one `A` per activity).
- **C (Consulted):** Subject matter expert providing inputs, review, or validation.
- **I (Informed):** Kept updated on progress, outcomes, or releases.

| Lifecycle Stage | Activity / Milestone | Business / PO 🔵 | Solution Arch 🟢 | Tech Lead 🟢 | Dev Team 🔴 | QA / Automation 🟠 | SecOps / CyberSec 🟡 | Platform / DevOps 🔘 | SRE / Observability 🔘 | Incident / Support | Automated CI/CD ⚙️ |
| :--- | :--- | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| **1. Strategy & Conception** | Business Need & Value Stream | **A / R** | C | I | I | I | I | I | I | I | - |
| | Technical Feasibility & MVP | C | **A** | R | C | I | C | C | I | - | - |
| | Architecture Decision Record (ADR) | I | **A** | R | C | I | C | C | I | - | - |
| | Threat Modeling & Abuse Cases | I | C | C | I | C | **A / R** | I | I | - | - |
| **2. Sprint Planning** | User Stories & Definition of Done | **A** | C | R | R | C | C | I | I | - | - |
| | Infrastructure & Cloud Capacity Planning | I | C | C | I | I | I | **A** | R | I | - |
| **3. Construction** | Test-Driven Development (TDD) | I | I | C | **R** | C | I | I | I | - | - |
| | Database Migrations & Versioning | I | C | **A** | R | I | I | C | I | - | - |
| | IaC Provisioning (Terraform) | I | C | C | I | I | C | **A / R** | C | - | - |
| | Real-time Lint & Security Pre-commits | I | I | **A** | R | I | C | I | - | - | R |
| | Pull Request Code Review | I | I | **A** | R | I | C | C | - | - | - |
| **4. Automated Gates** | Build & Container Packaging | I | I | I | I | I | I | C | I | - | **A / R** |
| | SAST & SonarQube Quality Gate | I | I | C | R | I | **A** | I | - | - | **R** |
| | Container & Dependency CVE Scanning | I | I | I | R | I | **A** | C | - | - | **R** |
| | IaC Security Linting (Trivy config / Conftest) | I | C | I | I | I | **A** | R | - | - | **R** |
| | API Contract Testing (Newman) | I | I | C | C | **A / R** | I | I | - | - | **R** |
| | Load & Performance Testing (k6) | I | C | C | C | **A / R** | I | C | C | - | **R** |
| | Dynamic Application Security (OWASP ZAP) | I | I | I | I | C | **A** | I | - | - | **R** |
| **5. Deployment** | Staging Promotion & Validation | I | I | C | I | C | C | **A / R** | C | - | **R** |
| | Production Gate Approval (CAB) | **A** | C | C | I | C | C | R | C | I | - |
| | Canary Traffic Shift (Istio 10% → 100%) | I | I | I | I | I | I | **A / R** | C | - | **R** |
| | Post-Deployment Smoke Probes | I | I | I | I | C | I | R | **A** | I | **R** |
| **6. Operations** | Metrics, Logs & Tracing Monitoring | I | I | I | I | I | I | C | **A / R** | I | - |
| | Incident Response (Sev 1 / Sev 2) | I | I | C | C | I | C | R | **A** | R | - |
| | Emergency Rollback Decision | I | C | C | I | I | I | R | **A** | I | **R** |
| | Blameless Post-Mortem & Remediation | C | C | R | R | I | C | R | **A** | C | - |

---

## 👥 Strategic Role Profiles & Accountabilities

```mermaid
classDiagram
    class ProductOwner {
        +DefineValueStream()
        +PrioritizeBacklog()
        +ApproveRelease()
    }
    class SolutionArchitect {
        +EvaluateADR()
        +Enforce4Plus1Model()
        +ReviewComponentSelection()
    }
    class TechLead {
        +ReviewPullRequests()
        +EnsureCodeStandards()
        +ApproveDBSchemas()
    }
    class CybersecurityEngineer {
        +ConductThreatModeling()
        +AuditVulnerabilities()
        +MaintainSecurityGates()
    }
    class DevOpsEngineer {
        +MaintainCI_CDPipelines()
        +ProvisionMultiCloudIaC()
        +ManageHelmReleases()
    }
    class SREEngineer {
        +DefineSLO_SLI()
        +OrchestrateChaosExperiments()
        +ConductPostMortems()
    }
    class IncidentManager {
        +CoordinateSev1Bridge()
        +EnsureMTTRReduction()
        +MaintainITSMTickets()
    }

    ProductOwner --> SolutionArchitect : Consults Feasibility
    SolutionArchitect --> TechLead : Guides Blueprint
    TechLead --> DevOpsEngineer : Collaborates CI/CD
    CybersecurityEngineer --> DevOpsEngineer : Injects Security Gates
    DevOpsEngineer --> SREEngineer : Handoff Deployment
    SREEngineer --> IncidentManager : Escalates Outages
```

### 1. Platform / DevOps Engineer
- **Mission:** Build and maintain immutable, self-healing multi-cloud infrastructure and high-velocity CI/CD delivery pipelines.
- **Key Responsibilities:**
  - Maintain Terraform code across Minikube, AWS EKS, Azure AKS, and GCP GKE.
  - Standardize Helm charts, KEDA scaling policies, and Istio service mesh configs.
  - Empower developers with automated, platform-specific local tooling (`platform-minikube.ps1`).

### 2. SRE (Site Reliability Engineer)
- **Mission:** Bridge software engineering and operations to ensure SLO compliance, resilience, and operational excellence.
- **Key Responsibilities:**
  - Establish SLIs and Error Budgets (e.g. 99.9% uptime, p95 latency < 500ms).
  - Execute chaos experiments and automated failovers.
  - Facilitate blameless post-mortems for major outages.

### 3. Observability Lead
- **Mission:** Provide unified visibility across telemetry signals (distributed traces, metrics, structured logs).
- **Key Responsibilities:**
  - Standardize OpenTelemetry instrumentations in GraphQL Router and Java/Go microservices.
  - Maintain Prometheus, Grafana, and Grafana Tempo dashboards.
  - Configure dynamic alert thresholds to prevent alert fatigue.

### 4. Incident Manager & Support (L1/L2/L3)
- **Mission:** Minimize Mean Time to Resolution (MTTR) and protect customer experience during outages.
- **Key Responsibilities:**
  - Coordinate emergency response war rooms for Severity-1 and Severity-2 incidents.
  - Synchronize incident lifecycle through ServiceNow / PagerDuty.
  - Ensure action items from incidents feed back into the product backlog.

---

## ⚖️ Architecture Decision Framework: Pugh Decision Matrix

For evaluating architectural candidates (e.g., choosing between Service Mesh providers, GraphQL Routers, or Messaging Brokers), teams must use the **Weighted Pugh Multi-Criteria Decision Matrix**.

### Example: GraphQL Federation Gateway Selection

| Decision Criteria | Weight (1-5) | Baseline: Apollo Gateway (Node.js) | Alternative A: WunderGraph Cosmo Router (Go) | Alternative B: Envoy GraphQL Filter |
| :--- | :---: | :---: | :---: | :---: |
| **High Throughput & Low Latency** | 5 | 0 (Baseline) | **+1** (Go native, 10x throughput) | +1 (C++ Envoy native) |
| **Apollo Federation v2 Compatibility** | 5 | 0 (Baseline) | **+1** (Full Federation v2 spec) | -1 (Partial / custom syntax) |
| **Observability & OpenTelemetry** | 4 | 0 (Baseline) | **+1** (Native OTel metrics & traces) | 0 (Standard Envoy metrics) |
| **Enterprise JWT / Keycloak Auth** | 4 | 0 (Baseline) | **+1** (JWKS caching & claims inject) | 0 (Lua/Wasm filter required) |
| **Operational Simplicity & Footprint** | 3 | 0 (Baseline) | **+1** (< 50MB RAM vs 300MB Node.js) | 0 (Envoy binary) |
| **Custom Plugin Extensibility** | 3 | 0 (Baseline) | **0** (Go / TypeScript plugins) | -1 (Complex C++/Wasm) |
| **Weighted Score** | - | **0.00** | **+21 (WINNER)** | +2.00 |

> [!NOTE]
> All architecture changes impacting cross-service communication or storage backends require an approved **ADR** backed by a Pugh Matrix before merging into `develop`.

---

## 🔁 Continuous Improvement & Feedback Loop

The DevSecOps lifecycle is circular:

```
  [ServiceNow Incident / Jira Ticket]
                 │
                 ▼
     [Severity Assessment (P1 - P4)]
                 │
                 ▼
  [SRE War Room & Mitigation (Hotfix / Rollback)]
                 │
                 ▼
  [Blameless Post-Mortem within 48h]
                 │
                 ▼
  [Automated Regression Test Added to Newman / k6]
                 │
                 ▼
   [Preventive Architectural Enabler in Sprint Backlog]
```

1. **Incident Resolution:** SRE and Dev collaborate to restore service within SLO.
2. **Root Cause Analysis (RCA):** The team identifies systemic flaws (e.g., missing network policy, unindexed database query).
3. **Automated Protection:** An automated test (Postman contract test, k6 load scenario, or SonarQube rule) is created so the defect cannot recur.
4. **Backlog Refinement:** The Product Owner allocates capacity in the next sprint for architectural hardening.
