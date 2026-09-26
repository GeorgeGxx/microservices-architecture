# ☸️ Local Deployment & Kubernetes Operations Guide (Docker Compose & Minikube)

> Complete manual for running the microservices ecosystem locally: Docker Compose (15 services), Minikube, Istio Service Mesh, and Cluster Resiliency.

---

## ✅ Prerequisites

| Tool | Version | Required for |
| :--- | :---: | :--- |
| Docker & Docker Compose | Latest | Quick Start (full stack) |
| Java (JDK) | 21 | Building/running Spring Boot services standalone |
| Maven | 3.9+ | Java multi-module reactor build |
| Node.js & npm | 22+ | React 19 + Tailwind v4 frontend |
| kubectl | 1.37.0 | Kubernetes / Minikube deployment |
| Minikube | 1.39.0 | Local Kubernetes deployment |
| Istioctl | 1.31.1 | Service mesh install & Kiali dashboard |
| Terraform | 1.16.2 | AWS / Azure / GCP provisioning |
| Cloudflared CLI | 2026.9.1 | Cloudflare tunnels deployment |
| PowerShell (`pwsh`) | 7+ | Running the automation scripts in `scripts/` |
| Python3 (`python`) | 3.11+ | Running the automation scripts in `scripts/` |

**Recommended local resources:** 8 CPU cores and 16 GB RAM (allocating up to 6 CPUs and 12 GB RAM to Minikube, leaving 2 CPUs and 4 GB RAM for Windows OS and IDE) — the full Docker Compose stack runs ~20 containers (5 microservices, frontend, Keycloak, Postgres, Kafka, Redis, and the Grafana LGTM observability stack).

> ⚠️ **Security note:** the Keycloak realm, test users (`admin_user`/`admin`, `basic_user`/`password`), and Grafana login (`admin`/`admin`) shown throughout this README are seeded for **local development only**. Rotate all credentials and secrets before using this stack in a shared or production environment.

---

### ⚙️ Kubernetes Workload Right-Sizing & Production Resource Allocation
All microservices and infrastructure pods are pre-configured with enterprise resource requests and limits to guarantee sub-millisecond execution, prevent GC pauses, and avoid `OOMKilled` eviction (optimized for Minikube clusters running with 6 CPUs and 12 GB RAM, reserving 2 cores and 4 GB RAM for Windows):

| Workload / Component | CPU Request | CPU Limit | Memory Request | Memory Limit | Ephemeral Storage | Architectural Focus |
| :--- | :---: | :---: | :---: | :---: | :---: | :--- |
| **Spring Cloud API Gateway** | `400m` | `2000m` | `512Mi` | `1536Mi` | `1Gi` | Reactive reverse proxy, Token Relay & CORS |
| **Spring Boot Microservices (x4)** | `400m` | `2000m` | `512Mi` | `1536Mi` | `1Gi` | Java 21 Virtual Threads concurrency |
| **Keycloak 26.7.3 IAM** | `300m` | `1000m` | `512Mi` | `1024Mi` | `1Gi` | Optimized JVM heap (-Xms256m -Xmx768m) |
| **HashiCorp Vault 2.0.4** | `150m` | `500m` | `256Mi` | `512Mi` | Standard | Dynamic secrets engine & KMS encryption |
| **Apache Kafka (KRaft Broker)** | `200m` | `1000m` | `512Mi` | `1024Mi` | `2Gi` | High-throughput event streaming |
| **PostgreSQL (x4 Databases)** | `100m` | `500m` | `256Mi` | `512Mi` | `512Mi` | Isolated stateful per-service persistence |
| **Redis 8 Cache & Token Bucket** | `100m` | `250m` | `128Mi` | `256Mi` | `256Mi` | Distributed rate limiting & catalog cache |
| **Frontend React 19 SPA (Nginx)** | `50m` | `200m` | `64Mi` | `128Mi` | `256Mi` | Distroless client asset delivery |
| **Prometheus 3 Metrics Server** | `200m` | `1000m` | `256Mi` | `1024Mi` | `2Gi` | 10s scraping & PromQL evaluation |
| **Grafana LGTM Stack (Dashboards)** | `100m` | `500m` | `128Mi` | `512Mi` | `1Gi` | Correlated trace, log & metric visualization |
| **Grafana Loki (Log Ingestion)** | `150m` | `800m` | `256Mi` | `1024Mi` | `2Gi` | Centralized container log indexing |
| **Grafana Tempo (Tracing Backend)** | `100m` | `500m` | `192Mi` | `512Mi` | `1Gi` | W3C distributed trace span storage |
| **Kiali Visual Mesh Topology** | `150m` | `600m` | `256Mi` | `512Mi` | `1Gi` | Real-time Istio Service Mesh visualizer |

---

## 🛠️ Winget DevSecOps & Platform CLI Tool Suite

The platform standardizes **17 essential industry-standard CLI applications** managed via Windows Package Manager (`winget`):

### 1. IaC & FinOps
- **`Hashicorp.Terraform` (`terraform`)**: Multi-cloud Infrastructure as Code engine.
- **`TerraformLinters.tflint` (`tflint`)**: Framework linter enforcing module conventions and catching provider errors.
- **`Infracost.Infracost` (`infracost`)**: Cloud cost estimation engine for Terraform.
- **`Graphviz.Graphviz` (`dot`)**: Dependency graph visualization utility (`terraform graph | dot -Tpng -o graph.png`).

### 2. DevSecOps & Security
- **`Gitleaks.Gitleaks` (`gitleaks`)**: Secret scanner detecting hardcoded credentials in Git history and uncommitted changes.
- **`AquaSecurity.Trivy` (`trivy`)**: Vulnerability scanner for container images, Helm charts, and IaC files.
- **`Sigstore.Cosign` (`cosign`)**: Container image signing and supply chain verification.
- **`Hashicorp.Vault` (`vault`)**: Client for HashiCorp Vault (KV-v2 secrets, PKI engine).

### 3. Container & Kubernetes Orchestration
- **`Docker.DockerDesktop` (`docker`)**: Local container engine and runtime.
- **`Kubernetes.minikube` (`minikube`)**: Local Kubernetes cluster driver.
- **`Kubernetes.kubectl` (`kubectl`)**: Kubernetes cluster management CLI.
- **`Helm.Helm` (`helm`)**: Kubernetes package manager for umbrella chart deployment.
- **`istioctl` (`istioctl`)**: Service mesh control plane and traffic management CLI.

### 4. Runtimes, Build Tools & Productivity
- **`Apache.Maven` (`mvn`)**: Java build engine for Spring Boot microservices.
- **`OpenJS.NodeJS.LTS` (`node`)**: JavaScript runtime for React frontend compilation.
- **`Git.Git` (`git`)**: Distributed version control system.
- **`Cloudflare.cloudflared` (`cloudflared`)**: Zero-trust client for secure encrypted tunnels.

> ℹ️ **Explicitly Excluded Tools (Zero Overhead):**  
> To keep developer workstations lightweight and eliminate redundant tooling, the auditor **strictly ignores**: *OpenTofu, k9s, kubectx, kubens, argocd cli, kustomize, eksctl, lazygit, jq, yq*.

---

## 💻 Local Standalone Development

To develop or debug microservices individually outside Docker:

### 1. Spring Boot Microservices (Java 21 / Maven)
```powershell
# Compile entire reactor
mvn clean compile

# Run specific service with dev profile
mvn spring-boot:run -pl products-service
mvn spring-boot:run -pl orders-service
mvn spring-boot:run -pl inventory-service
mvn spring-boot:run -pl notification-service
```

### 2. React 19 SPA (Vite + TailwindCSS v4)
```powershell
cd frontend
npm install
npm run dev
```

**Key Frontend, Mobile PWA & Storefront Features (`http://localhost:4200`):**
- **Hardware-Agnostic Universal QR & Barcode Engine:**
  - 📷 **Live Camera Stream (WebRTC):** Lens switching (front/rear), flashlight/torch toggle, and real-time laser animation.
  - 📁 **Image File Upload:** Drag-and-drop or file picker decoding of QR codes and barcodes.
  - 🔌 **USB & Bluetooth Laser Scanners (HID Wedge):** Real-time keystroke burst interceptor ($< 45\text{ ms}$) enabling $100\%$ driverless plug-and-play barcode guns (Honeywell, Zebra, Tera).
  - 🎨 **Dynamic QR Vector Generation:** On-demand SVG/Canvas QR labels for product shelf tags and order pickup receipts.
- **Enterprise Multi-Step Checkout & Logistics (Amazon & Mercado Libre):**
  - 📍 **Persistent Recipient Profile:** Automatic `localStorage` persistence (`msa_shipping_address`) enabling 1-click address recall for repeat buyers.
  - 🚚 **Tiered Delivery & DHL Tracking:** Real-time choice between Free Standard Shipping (3-5 days) and ⚡ DHL Express Priority ($9.99, 24-48h) with automated `DHL-XXXXXXXX` tracking generation.
  - 💳 **Real-Time Card Brand Detection:** Instant IIN/BIN recognition (Visa, Mastercard, AMEX) with dynamic cardholder validation, CVV security, and 256-bit SSL badges.
- **Product Catalog Social Proof & Verified Ratings:**
  - Verified buyer ratings (`★ 4.8 / 5.0`), total rating count derivations (`(1,240 ratings)`), `#1 Best Seller` ecommerce amber badges (`#e67a00`), and real-time stock availability pills.
- **Admin Operations Console & Real-Time Health LED:**
  - Dedicated admin gear icon in the navbar with an embedded dynamic health LED ("foquito sutil" 🟢/🟠/🔴) reflecting real-time microservices reachability, paired with a centralized `/admin` dashboard featuring 4-second animated `LIVE SYNC` inventory polling (infrastructure telemetry delegated to Grafana).
- **Order Lifecycle, Reverse Chronological Pagination & Saga Rollback:**
  - 🔄 **Reverse Chronological History:** Latest orders automatically appear on Page 1; oldest purchases are paginated to the final page.
  - 📑 **5-Stage Lifecycle Tabs:** Responsive wrapping (`flex-wrap: wrap`) for `All Orders`, `Processing` (`PLACED`), `Shipped` (`SHIPPED`), `Delivered` (`DELIVERED`), and `Cancelled` (`CANCELLED`), eliminating hidden horizontal clipping on mobile viewports.
  - 📦 **Structured Two-Tier Order Item Cards:** Upper tier displays thumbnail, full title (line-clamped), and mono SKU tag; lower tier clearly pairs quantity and unit price (`[Qty: 1] × $1,299.99`) with an emerald-highlighted subtotal.
  - ⚡ **Admin Logistics & Compensation Matrix:** Symmetrical 2x2 action grid for `Re-Order`, `View Receipt & QR`, `Dispatch (Ship)` / `Mark Delivered`, and `Cancel Order` ensuring 100% button visibility on smartphones without overflowing.
  - 📄 **Non-Clipping Mobile Pagination:** Ergonomic pagination controls with responsive button wrapping preventing `Next` button clipping.
- **Progressive Web App (PWA) & Responsive Mobile UX:**
  - 🔔 **Viewport-Bounded Notifications Drawer:** Fixed position mobile dropdown (`position: fixed; max-width: 400px;`) with auto-dismiss backdrop and word breaking for long codes.
  - 📱 **Mobile Storefront PWA:** Standalone installation (`manifest.webmanifest`), floating scan FAB button, camera WebRTC barcode scanner, and haptic vibration (`navigator.vibrate`).
- **OIDC PKCE Security:** Secure authentication flow via Keycloak 26.7.3 with automatic JWT token management and route guards.

---

## 🚀 Quick Start with Docker Compose

### 1. Launch Keycloak (Auth Layer)
Keycloak and its PostgreSQL database must be initialized first:

```powershell
# 1. Clone the repository and navigate to project directory
cd microservices-architecture

# 2. Copy environment file if not already present
cp .example.env .env

# 3. Start Keycloak and its database in detached mode
docker compose up -d --build keycloak

# 4. Verify Keycloak is healthy
docker compose ps keycloak
```

### 2. Bootstrap Keycloak (Clients, Users & Secrets)
Run the bootstrap script to create realm `microservices-realm`, configure public and confidential clients, generate passwords, and **automatically synchronize `KEYCLOAK_CLIENT_SECRET` into your `.env`**:

```powershell
# Native PowerShell script (auto-syncs client secret into .env):
pwsh -File .\scripts\auth\bootstrap-keycloak.ps1
```

#### Pre-Configured Test Users:
| Username | Password | Roles | Purpose |
| :--- | :--- | :--- | :--- |
| **`admin_user`** | `admin` | `ADMIN`, `USER` | Full administration & product management |
| **`basic_user`** | `password` | `USER` | Browsing catalog & placing orders |

### 3. Launch Full Microservices Ecosystem
Once Keycloak is bootstrapped and `.env` has the synced client secret, spin up all remaining containers (microservices, databases, messaging, LGTM observability stack, and HashiCorp Vault). 

**HashiCorp Vault v2.0.4** will auto-initialize via the [`vault-init`](./compose.yaml) container on startup:

```powershell
# Build and launch all services in detached mode
docker compose up -d --build

# Check real-time container health
# Note: It's OK if the vault-init service has exited in Docker Compose.
docker compose ps -a
```

### 4. Useful Docker Compose Commands:
```powershell
# View aggregated live logs
docker compose logs -f

# View logs for a specific service
docker compose logs -f apollo-router

# Graceful shutdown & volume teardown
docker compose down -v
```

---


---

## ☸️ Local Kubernetes Deployment (Minikube, Istio Mesh & Canary Operations)

The unified deployment orchestrator automates the complete lifecycle end-to-end: Minikube cluster provisioning, **Istio Service Mesh with Envoy sidecars**, Zero-Trust mTLS, **Kiali Visual Topology**, **Keycloak IAM bootstrap**, **HashiCorp Vault v2.0.4**, PostgreSQL databases, Kafka, and microservices:

### 1. 🚀 One-Shot Cluster Deployment
Deploy the entire infrastructure, security, mesh, and microservices in a single command:
```powershell
# Unified Enterprise CLI Orchestrator (Installs Minikube, Istio, Vault, Keycloak + db-keycloak, DBs, Apps & Tunnels):
.\platform.ps1 up

# Options & Variations:
# Deploy with Istio Service Mesh & Envoy sidecars (default):
.\platform.ps1 up -WithIstio

# Deploy in Native K8s Mode without Istio/Envoy overhead:
.\platform.ps1 up -WithoutIstio

# Deploy with canary version v2 enabled (90/10 traffic split):
.\platform.ps1 up -DeployCanary

# Fast-track bootstrap skipping security scans (Gitleaks/TFLint/Trivy):
.\platform.ps1 up -SkipScans

# Optional: Build all container images from Dockerfiles and deploy to the cluster (re-applies on existing cluster)
.\platform.ps1 up -Build

# Optional: Clean/destroy cluster first, then create and build everything from scratch
.\platform.ps1 down -Destroy
.\platform.ps1 up -Build

# Custom hardware sizing:
.\platform.ps1 up -Cpus 6 -MemoryMb 12288 -DiskSize 40g
```

> 💡 **Smart Image Synchronization & Adaptive Observability:**
> - **Zero-Rebuild Fallback:** The orchestrator automatically synchronizes any missing local Docker images into Minikube in seconds (`minikube image load`).
> - **Standardized Image Nomenclature:** Strictly enforces the production naming format `georgegxx/<service>:1.0.0` across both Docker Compose and Minikube environments, preventing untagged duplicates or namespace collisions.
> - **Adaptive Scraping:** Prometheus dynamically discovers Envoy sidecars and `istiod` when Istio is active, and cleanly monitors Actuator metrics across all microservices.

### 2. 🔍 Verify Mesh Health & Zero-Trust Policies
Audit proxy synchronization and mutual TLS enforcement without needing browser tunnels:
```powershell
# Audit platform health, pods, NodePorts, and Gatekeeper OPA policies:
.\platform.ps1 doctor
```

> 🔒 **Zero-Trust Security & In-Mesh Telemetry Architecture:**
> - **STRICT mTLS Mesh:** Enforces `PeerAuthentication: STRICT` across the `dev` namespace with short-lived X.509 SPIFFE identities issued by `istiod`.
> - **Selective Actuator Scraping:** Ports `8080` and `8001-8004` feature `portLevelMtls: PERMISSIVE` in `k8s/istio/peer-authentication-dev.yaml`, enabling Prometheus to scrape Actuator metrics without `connection reset by peer` errors while business traffic remains 100% encrypted.
> - **Kafka SASL Authentication (Port 9094):** Microservices produce and consume events through `kafka:9094` using SASL PLAIN (`app` credentials). In-mesh traffic benefits from **Defense-in-Depth** (Layer 7 SASL identification + Layer 4 Istio mTLS wire encryption).
> - **JVM & Resource Tuning:** Configured with `JAVA_TOOL_OPTIONS: -XX:+ExitOnOutOfMemoryError -XX:InitialRAMPercentage=40.0 -XX:MaxRAMPercentage=75.0 -XX:+TieredCompilation -XX:TieredStopAtLevel=1` and optimized HikariCP pools (`maximum-pool-size: 5`), accelerating cold container startup from 45s down to 10-13s.


### 3. 🌐 Open Local Browser Tunnels & Endpoint Access
Expose all internal services and web consoles to `localhost`:
```powershell
# Launch or supervise all background port-forward tunnels:
.\platform.ps1 tunnels

# Display formatted table of active URLs and credentials:
.\platform.ps1 urls
```

Once tunnels are active, access local web interfaces:
- **Frontend SPA:** [http://localhost:4200](http://localhost:4200)
- **API Gateway:** [http://localhost:8080](http://localhost:8080)
- **Keycloak Admin:** [http://localhost:8181](http://localhost:8181) (`admin` / `admin`)
- **Vault Web UI:** [http://localhost:8200](http://localhost:8200) (Token: `root`)
- **Kiali Mesh Topology:** [http://localhost:20001/kiali](http://localhost:20001/kiali)
- **Grafana Observability (Metrics, Logs & Tempo Traces):** [http://localhost:3000](http://localhost:3000) (`admin` / `admin`)
- **Prometheus Dashboard:** [http://localhost:9090](http://localhost:9090)
- **ArgoCD Web UI:** [http://localhost:8080](http://localhost:8080)

Alternatively, access services directly via Minikube NodePort without background tunnels:
- **Frontend SPA:** `http://$(minikube ip):30080`
- **API Gateway:** `http://$(minikube ip):30088`
- **Keycloak Admin:** `http://$(minikube ip):30181`
- **Vault Web UI:** `http://$(minikube ip):30820`
- **Kiali Visual Mesh:** `http://$(minikube ip):32001/kiali`
- **Grafana LGTM:** `http://$(minikube ip):30300`
- **Prometheus:** `http://$(minikube ip):30090`
- **ArgoCD Web UI:** `http://$(minikube ip):30808`

> 💡 **Production Compute Allocation:** All Kubernetes workloads and infrastructure manifests are engineered with **production-grade Right-Sizing**. Review the complete [Kubernetes Workload Right-Sizing & Production Resource Allocation](#️-kubernetes-workload-right-sizing--production-resource-allocation) matrix for detailed CPU, memory, and storage limits.

### 4. 🔀 Traffic Routing & Progressive Canary Rollouts
Execute advanced traffic shaping and Canary weight adjustments using Istio VirtualServices:
```powershell
# Deploy Canary V2 deployment:
kubectl apply -f k8s/istio/canary-deployment-products-v2.yaml

# Apply Canary traffic split (90% v1 / 10% v2):
kubectl apply -f k8s/istio/virtual-services.yaml
```

### 5. 🛑 Cluster Teardown & Resource Cleanup
Clean up all background tunnels, port-forwards, and stop or purge the Minikube cluster:
```powershell
# Stop and pause the Minikube cluster (preserves storage and state):
.\platform.ps1 down

# Or completely purge Minikube cluster and all persistent volumes:
.\platform.ps1 down -DeleteCluster
```

### Useful commands

```powershell
# Check running microservices in the dev namespace
kubectl get pods -n dev # Or -A for all namespaces

# Check the keycloak startup
kubectl describe pod -l app=keycloak -n dev | Select-String -Pattern "Startup" -Context 2,10
```
```powershell
# Verify that the Vault secrets were injected.
# Docker Compose
docker exec -it vault vault kv get secret/products-service
docker exec -it vault vault kv get secret/orders-service
docker exec -it vault vault kv get secret/inventory-service
docker exec -it vault vault kv get secret/notification-service

# Minikube

# View the Vault Pod and status in Minikube
kubectl get pods -n vault

# Retrieve a secret directly from the Vault Pod
kubectl exec -it -n vault deploy/vault -- vault kv get secret/products-service

# View the policies configured in Vault
kubectl exec -it -n vault deploy/vault -- vault policy list

# Access the Vault web interface on Minikube (Vault UI)
kubectl port-forward -n vault deploy/vault 8200:8200

# Open in browser
http://localhost:8200 (Token: root)

# Direct option using the Vault deployment
kubectl exec -it -n vault deploy/vault -- vault kv get secret/products-service
kubectl exec -it -n vault deploy/vault -- vault kv get secret/orders-service
kubectl exec -it -n vault deploy/vault -- vault kv get secret/inventory-service
kubectl exec -it -n vault deploy/vault -- vault kv get secret/notification-service
# Or by selecting the Pod using its label
kubectl exec -it -n vault (kubectl get pod -n vault -l app=vault -o jsonpath="{.items[0].metadata.name}") -- vault kv get secret/products-service

# Vault Agent Sidecar Injector
# 1. View the secrets file generated by Vault inside the container.
kubectl exec -it <pod-name> -- cat /vault/secrets/database.env
# 2. View the logs for the 'vault-agent' sidecar container.
kubectl logs <pod-name> -c vault-agent

# Verify Enterprise Vault Capabilities (Docker Compose)
# 1. Dynamic Database Credential Generation (PostgreSQL on-the-fly user):
docker exec -it vault vault read database/creds/products-db-role

# 2. Transit Encryption as a Service (Encrypt & Decrypt on-the-fly):
# Encrypt:
docker exec -it vault vault write transit/encrypt/microservices-data-key plaintext=$(echo -n "CreditCard-4111222233334444" | base64)
# Decrypt:
docker exec -it vault vault write transit/decrypt/microservices-data-key ciphertext="<ciphertext_value>"

# 3. Verify Least-Privilege Policies:
docker exec -it vault vault policy list
docker exec -it vault vault policy read products-service-policy

# 4. View Real-Time Vault Audit Log:
docker exec -it vault cat /vault/file/vault_audit.log


```

---

## 🛡️ Production-Grade Cluster Resiliency & Advanced Operations

The platform includes 5 production-grade operational capabilities configured for zero-cloud cost local Minikube deployment and enterprise readiness:

```mermaid
flowchart TD
    subgraph EventSources["⚡ Event Sources & Telemetry"]
        KAFKA[Apache Kafka: orders-topic<br/>Consumer Lag Monitoring]
        PROM_METRICS[Prometheus Metrics<br/>Gateway HTTP RPS & Latency]
        K8S_RES[K8s Resource Metrics<br/>CPU & Memory Utilization]
    end

    subgraph Autoscaling["⚖️ KEDA v2.20.1 & HPA Integration"]
        KEDA_OP[KEDA Operator v2.20.1<br/>Namespace: keda]
        SO_NOTIF[ScaledObject: notification-service<br/>Trigger: Kafka Lag & CPU]
        SO_GW[ScaledObject: apollo-router<br/>Trigger: Prometheus RPS & CPU]
        HPA[Unified Kubernetes HPA<br/>Controlled by KEDA]
        PDB[PodDisruptionBudgets<br/>minAvailable: 1]
    end

    subgraph Workloads["📦 Microservices Deployments"]
        PODS[Microservices Pods<br/>Min: 1 | Max: 3 (Host Safe)]
    end

    KAFKA --> KEDA_OP
    PROM_METRICS --> KEDA_OP
    K8S_RES --> KEDA_OP
    KEDA_OP --> SO_NOTIF
    KEDA_OP --> SO_GW
    SO_NOTIF --> HPA
    SO_GW --> HPA
    HPA -->|Scale Pods 1..N| PODS
    PDB -->|Guarantees Quorum| PODS
```

### 1. ⚖️ KEDA v2.20.1 Event-Driven Autoscaling & HPA Orchestration
* **Architecture & Coexistence:** KEDA does not replace Kubernetes `HorizontalPodAutoscaler` (HPA); it acts as an intelligent controller that creates and continuously synchronizes native `autoscaling/v2` HPA resources. To prevent flapping and replica race conditions, subcharts conditionally decouple native static HPAs when `keda.enabled=true`.
* **Kafka Consumer Lag Trigger (`notification-service`):** Scales pods dynamically in response to pending messages in the `orders-topic` partition queue (`lagThreshold: 10`), ensuring fast consumer drain under bulk checkout spikes.
* **Prometheus RPS Trigger (`apollo-router`):** Evaluates real-time HTTP Request Per Second rates using PromQL (`sum(rate(apollo_router_http_requests_total[1m]))`) scaling before CPU threshold saturation occurs.
* **CPU & Memory Stabilization:** ScaledObjects bundle resource utilization targets ($70\%$ CPU, $80\%$ Memory) alongside event triggers into a single unified HPA.
* **Zero-Downtime Guarantee (PDB):** Each microservice maintains `minAvailable: 1`, ensuring cluster upgrades, node drains, and evictions never compromise platform quorum.
* **Verification Commands:**
  ```powershell
  # Inspect KEDA ScaledObjects
  kubectl get scaledobjects -n dev

  # Inspect KEDA-generated HorizontalPodAutoscalers
  kubectl get hpa,pdb -n dev
  ```

### 2. 🔐 External Secrets Operator (ESO) & HashiCorp Vault Synchronization
* **Operator Engine:** External Secrets Operator deployed in `external-secrets` namespace using API `external-secrets.io/v1`.
* **SecretStore (`vault-secret-store`):** Authenticates to HashiCorp Vault using root token with `refreshInterval: 1h`.
* **ExternalSecret (`microservices-external-secret`):** Automatically maps and pulls secrets from Vault KV paths (`secret/data/application`, `secret/data/orders-service`) and merges them directly into the staging Kubernetes secret `microservices-secrets`.
* **Vault Seeding Script:**
  ```powershell
  # Seed secrets into Kubernetes Vault pod:
  $vaultPod = (kubectl get pods -n vault -l app=vault -o jsonpath="{.items[0].metadata.name}")
  kubectl exec -n vault $vaultPod -- vault kv put secret/application spring.datasource.username=postgres spring.datasource.password=admin jwt.secret=super-secure-jwt-secret-key-for-microservices-dev-environment-12345
  ```
* **Verification Command:**
  ```powershell
  kubectl get secretstore,externalsecret -n staging
  ```

### 3. 🌐 Progressive Canary Deployments in Istio Service Mesh
* **Traffic Splitting:** Istio `VirtualService` (`products-service-vs`) and `DestinationRule` (`products-service-dr`) allow fine-grained traffic shifting between stable `v1` and canary `v2` pods.
* **Instant Header Bypass:** Requests containing header `x-canary: true` route $100\%$ to the canary subset regardless of percentage weight, enabling safe QA verification before public traffic exposure.
* **Automated Progressive Rollout Scripts:**
  ```powershell
  # Set arbitrary traffic split (e.g. 80% to v1, 20% to v2):
  .\scripts\istio\set-canary-weight.ps1 -Service "products-service" -V1Weight 80 -V2Weight 20 -Namespace "staging"

  # Run automated progressive canary promotion (10% -> 25% -> 50% -> 100%):
  .\scripts\istio\auto-canary-rollout.ps1 -Service "products-service" -Namespace "staging" -StepIntervalSeconds 30
  ```

### 4. 🚨 Alertmanager Alert Routing (Local Default, Slack & Jira Ready)
* **Prometheus Rule Discovery:** `helm/microservices-umbrella/templates/prometheus-rule.yaml` labeled with `release: kube-prometheus`, allowing the Prometheus Operator to automatically discover and monitor alerts (`ServiceDown`, `HighErrorRate`, `HighLatency`, `HighHeapUsage`, `RedisExporterDown`).
* **AlertmanagerConfig CRD (`monitoring.coreos.com/v1alpha1`):** Deployed directly in the `staging` namespace with label `release: kube-prometheus`.
* **Active Default Local Receiver:** Routes alerts cleanly to `default-local-receiver` inside Alertmanager without failing or requiring external credentials.
* **Activating Slack Notifications:**
  1. Create the Slack incoming webhook secret in namespace `staging`:
     ```powershell
     kubectl create secret generic alertmanager-slack-webhook -n staging --from-literal=url='https://hooks.slack.com/services/YOUR/SLACK/WEBHOOK'
     ```
  2. In `helm/microservices-umbrella/values.yaml`, enable Slack:
     ```yaml
     alertmanagerConfig:
       slack:
         enabled: true
         channel: "#alerts-microservices"
     ```
* **Activating Jira Issue Creation:**
  1. Set up a Jira Automation incoming webhook rule or alert forwarder URL.
  2. In `helm/microservices-umbrella/values.yaml`, enable Jira:
     ```yaml
     alertmanagerConfig:
       jira:
         enabled: true
         webhookUrl: "https://automation.atlassian.com/pro/hooks/YOUR-JIRA-WEBHOOK-KEY"
     ```
  3. All `severity: critical` alerts will automatically trigger webhook payloads creating Jira issues.

---

