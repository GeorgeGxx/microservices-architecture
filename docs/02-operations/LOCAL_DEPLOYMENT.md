# ☸️ Local Deployment & Kubernetes Operations Guide (Docker Compose & Minikube)

> [!TIP]
> 🧭 **[Enterprise Platform Hub](../../README.md)** > **02. Operations** > `LOCAL_DEPLOYMENT.md`

> Complete manual for running the full microservices ecosystem locally with Docker Compose, Minikube, Istio Service Mesh, and cluster resiliency.

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
| Istioctl | 1.31.3 | Service mesh install & Kiali dashboard |
| Terraform | 1.16.2 | AWS / Azure / GCP provisioning |
| Cloudflared CLI | 2026.9.1 | Cloudflare tunnels deployment |
| PowerShell (`pwsh`) | 7+ | Running the automation scripts in `scripts/` |
| Python3 (`python`) | 3.11+ | Running the automation scripts in `scripts/` |

**Local Resource Profile & Allocation:**
- **Host Allocation:** 8+ CPU cores and 16–32 GB host RAM; reserve ~20 GiB for Docker Desktop and use Minikube settings of 8 CPUs, 16 GiB RAM, and 40 GB disk. This leaves headroom for background daemons and image caches while running the full stack (~20+ containers across microservices, datastores, MLOps, and observability).
- **MLOps Resource Footprint:** During automatic training runs, MLOps workloads request ~2.3 CPU cores and 4.75 GiB RAM in total (Kafka-to-Parquet capture, MLflow, and forecast API). Scheduled training Jobs execute only when data drift or threshold criteria are met.
- **Workload Right-Sizing Matrix:** For the complete per-service CPU/Memory requests, limits, storage reservations, operational ports, credentials, and architectural roles across all platform components, refer to the canonical [Ports & Service Matrix](../01-architecture/ARCHITECTURE.md#--ports--service-matrix) in `ARCHITECTURE.md`.

> ⚠️ **Security note:** The Keycloak realm, test accounts (`admin_user`/`admin`, `basic_user`/`password`), and Grafana credentials (`admin`/`admin`) documented across the platform are seeded for **local development only**. Rotate all credentials and secrets before using this stack in shared or production environments.

## 🛠️ Winget DevSecOps & Platform CLI Tool Suite

The Minikube entrypoint audits the local developer and deployment tool inventory. Each cloud entrypoint audits only Terraform, its matching provider CLI, and `kubectl`; those tools are not mixed into the local inventory.

### 1. IaC & FinOps
- **`Hashicorp.Terraform` (`terraform`)**: Multi-cloud Infrastructure as Code engine.
- **`TerraformLinters.tflint` (`tflint`)**: Framework linter enforcing module conventions and catching provider errors.
- **Krew `cost` plugin (`kubectl-cost`)**: Live Kubernetes workload-cost queries through OpenCost (`kubectl cost ... --opencost`). It is a kubectl plugin, not a separate OpenCost CLI binary.
- **`Graphviz.Graphviz` (`dot`)**: Dependency graph visualization utility (`terraform graph | dot -Tpng -o graph.png`).

### 2. DevSecOps & Security
- **`Gitleaks.Gitleaks` (`gitleaks`)**: Secret scanner detecting hardcoded credentials in Git history and uncommitted changes.
- **`AquaSecurity.Trivy` (`trivy`)**: Vulnerability scanner for container images, Helm charts, and IaC files.
- **`Sigstore.Cosign` (`cosign`)**: Cryptographic supply-chain verification (`devsecops/compliance/cosign/cosign.pub` + `supply-chain-manifest.json` verified in `.\platform-minikube.ps1 security-scan` and image verification in `.\platform-multicloud.ps1 pre-deploy`).
- **`Hashicorp.Vault` (`vault`)**: Client CLI for HashiCorp Vault (KV-v2 secrets, PKI engine).
  * **Server runtime vs. Host client:** The Vault server runs inside Kubernetes (Minikube `namespace: vault` or cloud EKS/AKS/GKE) exposed on port `8200` (`http://localhost:8200`). The local `vault.exe` on Windows functions as an interactive administrative and debugging client.
  * **Script automation:** Minikube routines (`.\platform-minikube.ps1 vault -VaultAction init|seed|rotate|status` and `.\platform-minikube.ps1 up`) automatically use the local host `vault` CLI when `http://localhost:8200` is reachable and fall back seamlessly to `kubectl exec` inside the containerized Vault pod so developers without an active port-forward can still run all automations.
  * **Connecting your host CLI to the cluster:**
    ```powershell
    $env:VAULT_ADDR = "http://localhost:8200"
    $env:VAULT_TOKEN = "root"
    vault status
    vault kv list secret/
    vault kv get secret/products-service
    ```

### 3. Container & Kubernetes Orchestration
- **`Docker.DockerDesktop` (`docker`)**: Local container engine and runtime.
- **`Kubernetes.minikube` (`minikube`)**: Local Kubernetes cluster driver.
- **`Kubernetes.kubectl` (`kubectl`)**: Kubernetes cluster management CLI.
- **`Helm.Helm` (`helm`)**: Kubernetes package manager for umbrella chart deployment.

OpenCost is reconciled by ArgoCD on Minikube and cloud clusters. Minikube reuses the existing kube-prometheus-stack; cloud clusters receive a resource-sized Prometheus chart through `argocd/applicationset-prometheus-cloud.yaml`. The OpenCost UI is available locally at [http://localhost:7000](http://localhost:7000) through the tunnel supervisor. Install the optional CLI plugin with `kubectl krew install cost`, then query the active context with `kubectl cost namespace --opencost --show-all-resources --window 1d`.

Cloud cluster entries managed by the cloud ApplicationSets must carry these Argo CD cluster-secret labels: `finops.opencost.io/enabled=true`, `finops.opencost.io/provider=aws|azure|gcp`, `environment=dev|staging|prod`, `data-plane=primary|dp1|dp2`, and `git-branch=develop|staging|main`. Use `primary` for dev/staging and `dp1`/`dp2` for the two production data planes. The Terraform tags/labels aid cloud-side cost allocation; OpenCost cloud-billing ingestion stays disabled until provider billing exports and credentials are configured.

Docker Compose does not install OpenCost: it can run the application containers but does not provide Kubernetes workload allocation data.

### PostgreSQL backup and restore drills

The Minikube bootstrap installs `k8s/common/bcdr/database-backup-cronjob.yaml` in the `data` namespace. It stores custom-format dumps for Keycloak, inventory, orders, and products on the `postgres-bcdr-backups` PVC every six hours, keeps a rolling seven-day window, and runs an isolated checksum plus restore verification weekly. The restore job does not connect to or modify the source databases.

```powershell
# Check the durable backup claim and scheduled jobs
kubectl get pvc,cronjobs -n data

# Run a backup immediately and inspect its logs
kubectl create job --from=cronjob/postgres-bcdr-backup "postgres-bcdr-backup-manual-$(Get-Date -Format yyyyMMddHHmmss)" -n data
kubectl get jobs -n data --sort-by=.metadata.creationTimestamp

# Run an isolated restore verification immediately
kubectl create job --from=cronjob/postgres-bcdr-restore-verification "postgres-bcdr-restore-manual-$(Get-Date -Format yyyyMMddHHmmss)" -n data
kubectl get jobs -n data --sort-by=.metadata.creationTimestamp
```

Use `kubectl logs -n data job/<job-name>` to confirm each database passed. The PVC survives pod restarts but is still inside the Minikube cluster; deleting the cluster deletes these local backups. For cloud disaster recovery, configure the existing Velero schedule with an encrypted off-cluster object-storage location and verify a restore into a separate cluster. The local PVC alone is not an offsite backup.

### FinOps controls and workload sizing

- **Live Kubernetes allocation:** `.\platform-minikube.ps1 cost` uses OpenCost through the optional Krew plugin. Cloud billing remains unavailable until provider billing exports and credentials are connected.
- **Seven-day request sizing:** `python scripts/local-cost-estimator.py rightsize` queries Prometheus for per-container CPU and memory peaks, compares them with Kubernetes requests, and reports advisory requests with headroom. It requires cAdvisor and kube-state-metrics series; it does not patch workloads. Docker Compose has no Kubernetes request metrics.
- **Illustrative USD estimate:** `python scripts/local-cost-estimator.py --env staging` uses the fixed architecture catalog, not a provider quote or Terraform plan cost. `--max-monthly-usd` can enforce a ceiling against that profile.
- **Cloud budget alerts:** AWS, Azure, and GCP Terraform environments support opt-in monthly budgets. Set `enable_monthly_cost_budget=true` and `monthly_cost_budget_usd` for the workspace. AWS/Azure also require `finops_alert_emails`; GCP requires `billing_account_id` and uses billing account notification recipients. Defaults are disabled. These thresholds notify but do not stop or scale resources. AWS CostCenter filtering requires activating that tag as a cost allocation tag in Billing.
- **CI estimate gates:** the manual AWS Terraform workflow reports the illustrative environment profile and a plan-derived monthly delta for a small AWS catalog. `FINOPS_MAX_MONTHLY_USD` enables the profile ceiling; `FINOPS_MAX_MONTHLY_DELTA_USD` enables a plan increase ceiling. The delta prices selected EKS control planes/node types, RDS classes/storage, NAT gateways, and load balancers only; it lists other changed types as unpriced, omits usage charges, and is not a complete quote.
- **`istioctl` (`istioctl`)**: Service mesh control plane and traffic management CLI.

### 4. Runtimes, Build Tools & Productivity
- **`Apache.Maven` (`mvn`)**: Java build & unit test engine (`.\platform-minikube.ps1 test` executes the Java 21 + Maven multi-module reactor test suite).
- **`BellSoft.LibericaJDK.21` (`java`)**: Java 21 runtime required by the Spring Boot services.
- **`OpenJS.NodeJS.LTS` (`node`)**: JavaScript runtime for React frontend compilation.
- **`Python.Python.3.11` (`python`)**: Runtime for the documented project automation and test scripts (3.11 or newer).
- **`Git.Git` (`git`)**: Distributed version control system.
- **`Cloudflare.cloudflared` (`cloudflared`)**: Zero-trust client for secure encrypted tunnels.

Use `.\platform-minikube.ps1 tools` to audit the local CLI inventory. Add `-Install` to install missing tools or `-InstallOpenCostPlugin` to install the optional OpenCost Krew plugin. Cloud-provider tools are owned by their respective cloud entrypoints and are not added to this local inventory. This does not install unrelated tools or change machine-wide environment variables.

> ℹ️ **Explicitly Excluded Tools (Zero Overhead):**  
> To keep developer workstations lightweight and eliminate redundant tooling, the auditor **strictly ignores**: *OpenTofu, k9s, kubectx, kubens, argocd cli, kustomize, eksctl, lazygit, jq, yq*.

---
 
## 🚀 Docker Compose Deep-Dive & Operations

> 💡 **Fast-Track Quick Start:** For the 3-minute TL;DR copy-paste guide, see [README.md (Option A: Local Docker Compose)](../../README.md#option-a-local-docker-compose-default-platform-stack). The sections below detail the operational mechanics, container lifecycle, and debugging procedures.

### 1. Launch Keycloak (Auth Layer)
Keycloak and its PostgreSQL database must be initialized first:
 
```powershell
# 1. Clone the repository and navigate to project directory
cd microservices-architecture
 
# 2. Copy environment file if not already present
cp .env.example .env
 
# 3. Start Keycloak and its database in detached mode
docker compose up -d --build keycloak
 
# 4. Verify Keycloak is healthy
docker compose ps keycloak
```
 
### 2. Bootstrap Keycloak (Clients, Users & Secrets)
Run the bootstrap script to create realm `microservices-realm`, configure public and confidential clients, generate passwords, and **automatically synchronize `KEYCLOAK_CLIENT_SECRET` into your `.env`**:
 
```powershell
# Native PowerShell script (auto-syncs client secret into .env):
pwsh -File .\scripts\bootstrap-keycloak.ps1
```
 
#### Pre-Configured Test Users:
| Username | Password | Roles | Purpose |
| :--- | :--- | :--- | :--- |
| **`admin_user`** | `admin` | `ADMIN`, `USER` | Full administration & product management |
| **`basic_user`** | `password` | `USER` | Browsing catalog & placing orders |
 
### 3. Launch the Default Docker Compose Stack
Once Keycloak is bootstrapped and `.env` has the synced client secret, start the full Compose stack (microservices, databases, messaging, LGTM observability stack, HashiCorp Vault, MLflow, and the demand-forecast API). MLflow and the forecast API start with the rest; the forecast feature needs sales history and a trained model before it can return predictions.
 
**HashiCorp Vault v2.2.0** will auto-initialize via the [`vault-init`](../../compose.yaml) container on startup:
 
```powershell
# Build and launch the complete platform stack in detached mode
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
docker compose logs -f cosmo-router
 
# Stop containers and networks; preserve named volumes and local MLOps history
docker compose down
```

Use `docker compose down -v` only when you intentionally want to delete persisted Compose data, including MLflow runs and model artifacts.
 
---
 
### 5. 🧪 Local MLOps Workflow with Docker Compose
 
The `training` and `capture` Compose profiles keep MLOps jobs out of the regular `docker compose up` startup. The PowerShell wrapper starts the capture service in the background when needed, so no second terminal must remain attached to Kafka.
 
#### 1. Start the platform
Complete the Keycloak bootstrap steps above, then launch the normal stack:
```powershell
docker compose up -d --build
```
This starts MLflow, the demand-forecast API, Kafka, and the other default services. The MLflow UI is available at <http://localhost:5000>. MLflow metadata and model artifacts persist in the `mlops_mlflow_data` and `mlops_mlflow_artifacts` Docker volumes without requiring MinIO.
 
#### 2. Train the demo model
```powershell
.\mlops\training.ps1 -Target compose
```
The Linux training image contains Java 17, PySpark 4.2.0, pandas 2.3.3 (the supported pandas 2.x line for Spark 4.2), scikit-learn, and MLflow. GitPython's optional Git executable warning is suppressed in the container because the image does not include a `.git` checkout; the run still records its metrics and artifacts normally. If `mlops/data/synthetic_sales.csv` does not exist, the job creates a deterministic 30-day example dataset there. It builds lag and calendar features with PySpark, trains a random forest, and logs the run, RMSE/MAE metrics, and model artifact to MLflow. The generated values demonstrate the pipeline and should not guide purchasing decisions.
 
To train from another CSV, place it under `mlops/data` and pass its container path:
```powershell
docker compose run --build --rm demand-model-training --input-csv /data/sales.csv
```
Or use the PowerShell convenience wrapper:
```powershell
.\mlops\training.ps1 --input-csv .\mlops\data\sales.csv
```
 
#### 3. Capture simulated or frontend orders (Optional)
The one-command simulation path starts capture automatically, publishes sample orders to Kafka, and waits for a new verified MLflow run:
```powershell
.\mlops\training.ps1 -Target compose -SimulateOrders -Days 14
```

For the natural storefront flow, start the listener in the background:
```powershell
.\mlops\training.ps1 -Target compose -StartCapture
```
Then create purchases in the frontend and complete delivery through the order workflow. Only `DELIVERED` order events are included. The background service consumes `orders-topic` at `kafka:9092`, stores order lines as partitioned Parquet in `mlops/data/sales_parquet`, and checkpoints under `mlops/data/checkpoints/sales_parquet`. Compose restarts the listener unless you stop it. Stop it with `docker compose stop demand-sales-capture`.

The automatic trainer requires at least 9 distinct date partitions and a stable 60-second Parquet snapshot; naturally created orders share their actual order dates, so the model will not train until enough distinct dates exist. The optional demo training step above creates an initial run immediately using synthetic data. For simulated Kafka data, the wrapper snapshots existing MLflow run IDs and verifies the new finished run, with a guarded training fallback if the capture-side auto-trainer does not publish in time. Its default timeout is 180 seconds; use `-RunTimeoutSeconds 300` for a longer wait. If the capture container restarts while processing the events, the wrapper stops waiting and prints its logs. Simulation cannot be combined with `--input-csv` or `--input-parquet` because it trains from the captured Kafka dataset.

#### 4. Train on the captured sales and select forecast data
After `sales_parquet` spans at least 9 calendar days per SKU:
```powershell
docker compose run --build --rm demand-model-training --input-parquet /data/sales_parquet
```
Or via the PowerShell script:
```powershell
.\mlops\training.ps1 --input-parquet .\mlops\data\sales_parquet
```
Set `MLOPS_SALES_FILE=sales_parquet` in `.env` so the forecast API reads that dataset, then recreate the container:
```powershell
docker compose up -d --force-recreate demand-forecast-service
```
 
#### 5. View the forecast and monitor operations
Sign in as `admin_user` and navigate to **Admin Console → Demand Forecast · 7 Days**. The API requires the Keycloak `ADMIN` role, loads the latest promoted champion model (`tags.model_role = 'champion'`) matching the active dataset from MLflow, and returns 7 daily estimates per SKU with data provenance. Non-improving training runs (`tags.model_role = 'challenger_rejected'`, `promotion_status = 'REJECTED_BY_QUALITY_GATE'`) remain logged in MLflow for audit and comparison without overwriting the active model served in the storefront.
 
MLflow provides training-run and metric comparison at <http://localhost:5000> by default. Compose and Minikube keep separate tracking databases, artifacts, and sales datasets; stop one runtime before starting the other if both use port 5000. To run both at once, bind Compose MLflow to port 5001 before starting it:
```powershell
$env:MLFLOW_PORT = "5001"
docker compose up -d --force-recreate mlflow
```
Minikube remains at `http://localhost:5000`, while Compose uses `http://localhost:5001`; the training wrapper resolves the Compose URL from Docker's port mapping. Do not use `docker compose down -v` for routine shutdown because it deletes Compose MLflow metadata and artifacts. Grafana has two dashboards: **Microservices Architecture · Technical & Security Operations (SRE)** covers forecast API availability, traffic, latency, and its contribution to the availability SLO; **E-Commerce Business Intelligence & Inventory Operations** covers forecast freshness, active model age, and RMSE/MAE alongside inventory indicators.
 
---

## 💻 Local Standalone Development

For targeted local debugging and feature development of individual components outside container environments:

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

### 2. Modernized Storefront Architecture (React 19 & TailwindCSS v4)
```powershell
cd frontend
npm install
npm run dev
```

**Key Architectural & Storefront Capabilities (`http://localhost:5173`):**
- **Context-Aware Global & Scoped Search:**
  - The navbar header search dynamically filters the product catalog and triggers a quick command palette.
  - The Orders & Tracking view scopes search to customer order history, and the Admin Console isolates filters to specific management tables (the header search is automatically hidden on the Orders view to prevent conflicting search fields).
- **Enterprise Wishlist & State Persistence:**
  - Adheres to mature e-commerce identity patterns: guest shoppers attempting to save items are prompted to authenticate via Keycloak, while authenticated users have favorites safely synchronized across sessions and devices (`localStorage` + backend state).
- **Role-Based Telemetry & Admin Controls:**
  - Administrative tools (QR/Barcode Scanner for inventory auditing, Admin Telemetry tab, warehouse controls) are strictly gated to users holding the Keycloak `ADMIN` role.
  - The navbar brand LED checks a lightweight GraphQL query every 30 seconds. Green means the frontend → Cosmo Router → Products subgraph path is reachable, amber means a check is in progress, and red means that path failed. Platform telemetry is monitored via Grafana.
- **Seven-Day Demand Forecast Panel:**
  - Dedicated admin tab reading the latest successfully registered MLflow model through `demand-forecast-service`.
  - Distinguishes synthetic demo data from captured sales and displays the latest observed training timestamp. Containerized PySpark training and Kafka Structured Streaming integrate directly without requiring host Python or Java runtime configurations (see [Local MLOps Workflow with Docker Compose](#5--local-mlops-workflow-with-docker-compose) and [Minikube MLOps Deployment](#5--minikube-mlops-deployment--automated-dynamic-training)).
- **Scoped Notification Feed (Server-Sent Events):**
  - Real-time Server-Sent Events (SSE) from `notification-service` are strictly isolated per authenticated user profile to protect transactional privacy (order confirmation, DHL tracking updates, stock alerts).
  - Features a viewport-bounded notifications drawer (`position: fixed; max-width: 400px;`) with auto-dismiss backdrop and word breaking for tracking IDs.
- **Hardware-Agnostic Universal QR & Barcode Engine:**
  - 📷 **Live Camera Stream (WebRTC):** Lens switching (front/rear), flashlight/torch toggle, and real-time laser animation.
  - 📁 **Image File Upload:** Drag-and-drop or file picker decoding of QR codes and barcodes.
  - 🔌 **USB & Bluetooth Laser Scanners (HID Wedge):** Real-time keystroke burst interceptor ($< 45\text{ ms}$) enabling $100\%$ driverless plug-and-play barcode guns (Honeywell, Zebra, Tera).
  - 🎨 **Dynamic QR Vector Generation:** On-demand SVG/Canvas QR labels for product shelf tags and order pickup receipts.
- **Enterprise Multi-Step Checkout & Logistics (Amazon & Mercado Libre):**
  - 📍 **Persistent Recipient Profile:** Automatic `localStorage` persistence (`msa_shipping_address`) enabling 1-click address recall for repeat buyers.
  - 🚚 **Tiered Delivery & DHL Tracking:** Real-time choice between Free Standard Shipping (3-5 days) and ⚡ DHL Express Priority ($9.99, 24-48h) with automated `DHL-XXXXXXXX` tracking generation.
  - 💳 **Local Payment Simulation:** Choose a demo-approved or demo-declined outcome. No payment card data is requested or stored; no payment provider or real charge is involved. A declined outcome does not create an order or decrement inventory.
- **Product Catalog Social Proof & Verified Ratings:**
  - Verified buyer ratings (`★ 4.8 / 5.0`), total rating count derivations (`(1,240 ratings)`), `#1 Best Seller` ecommerce amber badges (`#e67a00`), and real-time stock availability pills.
- **Order Lifecycle, Responsive Pagination & Saga Rollback:**
  - 🔄 **Reverse Chronological History:** Latest orders automatically appear on Page 1; oldest purchases are paginated to the final page.
  - 📑 **Order Status Filters:** Responsive filters for `All Orders`, `Placed` (`PLACED`), `In Transit` (`SHIPPED`), `Delivered` (`DELIVERED`), and `Cancelled` (`CANCELLED`). UI labels map directly to Orders Service enums; cancelled is terminal and is not shown as a fulfillment step.
  - 🚚 **Dispatch and Cancellation Rule:** A placed order can be cancelled before dispatch; once the admin dispatches it (`SHIPPED` / In Transit), cancellation is removed and the backend rejects it. Later changes arrive through the Kafka-backed `ORDER_NOTIFICATION` SSE event and are confirmed by refetching GraphQL state, with periodic polling as fallback.
  - 📦 **Structured Two-Tier Order Item Cards:** Upper tier displays thumbnail, full title (line-clamped), and mono SKU tag; lower tier pairs quantity and unit price (`[Qty: 1] × $1,299.99`) with an emerald-highlighted subtotal.
  - ⚡ **Admin Logistics & Compensation Matrix:** Symmetrical 2x2 action grid for `Re-Order`, `View Receipt & QR`, `Dispatch (Ship)` / `Mark Delivered`, and `Cancel Order`.
  - 📄 **Responsive Pagination:** Full pagination controls with items-per-page selectors and page counters across both the public product catalog and administrative data tables, featuring non-clipping mobile wrapping.
- **OIDC PKCE Security:** Secure authentication flow via Keycloak 26.8.1 with automatic JWT token management, role validation, and route guards.

---

## ☸️ Local Kubernetes Deployment (Minikube, Istio Mesh & Canary Operations)

> 💡 **Fast-Track Quick Start:** For the 3-minute TL;DR copy-paste guide, see [README.md (Option B: Local Kubernetes on Minikube)](../../README.md#option-b-local-kubernetes-on-minikube-enterprise-devsecops). The sections below detail the complete Istio service mesh tuning, Canary traffic split mechanics, KEDA autoscaling, and HashiCorp Vault injector operations.

The unified deployment orchestrator automates the complete lifecycle end-to-end: Minikube cluster provisioning, **Istio Service Mesh with Envoy sidecars**, Zero-Trust mTLS, **Kiali Visual Topology**, **Keycloak IAM bootstrap**, **HashiCorp Vault v2.2.0**, PostgreSQL databases, Kafka, and microservices:

### 1. 🚀 One-Shot Cluster Deployment
Deploy the entire infrastructure, security, mesh, and microservices in a single command:
```powershell
# Unified Enterprise CLI Orchestrator (Installs Minikube, Istio, Vault, Keycloak + db-keycloak, DBs, Apps & Tunnels):
.\platform-minikube.ps1 up

# Options & Variations:
# Deploy with Istio Service Mesh & Envoy sidecars (default):
.\platform-minikube.ps1 up -WithIstio

# Deploy in Native K8s Mode without Istio/Envoy overhead:
.\platform-minikube.ps1 up -WithoutIstio

# Build candidate source separately; -Build preserves the deployed stable products-service image.
# Use a unique immutable commit/build tag (initial split: 90% stable / 10% canary):
$candidateTag = "canary-$(git rev-parse --short HEAD)-$(Get-Date -Format yyyyMMddHHmmss)"
.\platform-minikube.ps1 up -Build -DeployCanary -CanaryImageTag $candidateTag

# Explicitly bypass local Gitleaks/TFLint/Trivy/Conftest gates:
.\platform-minikube.ps1 up -SkipScans

# Optional: Build all container images from Dockerfiles and deploy to the cluster (re-applies on existing cluster)
.\platform-minikube.ps1 up -Build

# Optional: Clean/destroy cluster first, then create and build everything from scratch
.\platform-minikube.ps1 down -Destroy
.\platform-minikube.ps1 up -Build

# Optional lower-memory profile (may constrain concurrent workloads and MLOps training):
.\platform-minikube.ps1 up -Cpus 6 -MemoryMb 12288
```

> 💡 **Smart Image Synchronization & Adaptive Observability:**
> - **Dedicated Least-Privilege RBAC:** Every microservice and MLOps component runs under an isolated `ServiceAccount` (`cosmo-router-sa`, `orders-service-sa`, etc.) with `automountServiceAccountToken: false` and empty cluster API permissions, preventing token theft and lateral movement.
> - **Fingerprint-Cached Images:** MLOps images are rebuilt only when their source fingerprint changes or neither a matching local image nor a matching cached Minikube image is available; Minikube is loaded only when its copy is absent or out of sync. The cache lives under `%LOCALAPPDATA%\microservices-architecture\minikube-image-cache`.
> - **Standardized Image Nomenclature:** Strictly enforces the production naming format `georgegxx/<service>:1.0.0` across both Docker Compose and Minikube environments, preventing untagged duplicates or namespace collisions.
> - **Adaptive Scraping:** Prometheus dynamically discovers Envoy sidecars and `istiod` when Istio is active, and cleanly monitors Actuator metrics across all microservices.

### 2. 🔍 Verify Mesh Health & Zero-Trust Policies
Audit proxy synchronization, RBAC service accounts, and mutual TLS enforcement without needing browser tunnels:
```powershell
# Audit platform health, pods, NodePorts, and Gatekeeper OPA policies:
.\platform-minikube.ps1 doctor
```

Run the local DevSecOps controls independently after the stack is reachable:

```powershell
.\platform-minikube.ps1 test            # Java 21 + Maven reactor unit test suite across microservices
.\platform-minikube.ps1 security-scan   # Gitleaks, TFLint, Trivy, Conftest, Cosign (cosign.pub)
.\platform-minikube.ps1 contract       # Newman API/auth collection
.\platform-minikube.ps1 performance    # k6 SLO suite in Docker
.\platform-minikube.ps1 dast           # OWASP ZAP baseline with devsecops/dast/zap/rules.tsv
```

For cloud targets, set `BASE_URL`, `TARGET_URL`, `FRONTEND_URL`, and `KEYCLOAK_URL` to reachable endpoints before running the corresponding checks. `contract`, `performance`, and `dast` are explicit commands; they do not generate load or scan the application during every `up`.

> 🔒 **Zero-Trust Security & In-Mesh Telemetry Architecture:**
> - **STRICT mTLS Mesh:** Enforces `PeerAuthentication: STRICT` across the `dev` namespace with short-lived X.509 SPIFFE identities issued by `istiod`.
> - **Selective Metrics Scraping:** Cosmo Router exposes HTTP metrics at Service port `http-metrics:9090`; the Service port name follows Istio's `<protocol>[-suffix]` convention so Envoy classifies it as HTTP. Spring Actuator ports `8001-8004` are configured for Prometheus scraping in `k8s/istio/peer-authentication-dev.yaml`; application traffic remains protected by STRICT mTLS.
> - **Kafka (PLAINTEXT, Port 9092):** Microservices produce and consume events through `kafka:9092`. Istio can report TCP connection metrics for this traffic; Kafka message contents remain application-level data.
> - **JVM & Resource Tuning:** Configured with `JAVA_TOOL_OPTIONS: -XX:+ExitOnOutOfMemoryError -XX:InitialRAMPercentage=40.0 -XX:MaxRAMPercentage=75.0 -XX:+TieredCompilation -XX:TieredStopAtLevel=1` and optimized HikariCP pools (`maximum-pool-size: 5`), accelerating cold container startup from 45s down to 10-13s.


### 3. 🌐 Open Local Browser Tunnels & Endpoint Access
Expose all internal services and web consoles to `localhost`:
```powershell
# Launch or supervise all background port-forward tunnels:
.\platform-minikube.ps1 tunnels

# Display formatted table of active URLs and credentials:
.\platform-minikube.ps1 urls
```
Running `.\platform-minikube.ps1 urls` automatically renders the formatted table of active `localhost` tunnels, Minikube NodePorts, and default credentials directly in the terminal.

> 🌐 **Canonical Endpoint & Documentation Matrix:** For the complete, interactive reference table listing all 16 direct `localhost` URLs, Minikube NodePorts, protocols, and OpenAPI Swagger UIs (Products, Orders, Inventory, Notification, Demand Forecast, MLflow, Keycloak, Vault, Grafana, Prometheus, Alloy, Kiali, ArgoCD, OpenCost), refer to the canonical [Unified Endpoints, Interactive Swagger & Console Access Matrix](../../README.md#-unified-endpoints-interactive-swagger--console-access-matrix) in `README.md`.

### 4. 🔀 Traffic Routing & Progressive Canary Rollouts
Deploy a distinct immutable candidate image, then shift Istio traffic in guarded stages. `platform-minikube.ps1 canary -Action rollout` checks both deployments stay Ready, pauses for observation in Grafana/Kiali at every stage, and restores the last accepted split if a gate fails or is declined:
```powershell
# Deploy the canary and start at 90% stable / 10% canary:
.\platform-minikube.ps1 up -DeployCanary -CanaryImageTag "<immutable-image-tag>"

# Change traffic manually; both weights must add up to 100:
.\platform-minikube.ps1 canary -Action weight -Namespace dev -V1Weight 75 -V2Weight 25

# Promote interactively through 10%, 25%, 50%, 75%, then 100% canary:
.\platform-minikube.ps1 canary -Action rollout -Namespace dev -Steps 10,25,50,75,100 -StepIntervalSeconds 30

# Immediate traffic rollback to stable v1; keeps the canary deployed for investigation:
.\platform-minikube.ps1 canary -Action weight -Namespace dev -V1Weight 100 -V2Weight 0
```

At 100% canary, v1 remains Ready but receives no normal traffic so it is available for a fast rollback. For final retirement, promote the exact tested image tag in `helm/values/values-minikube.yaml` and let ArgoCD sync the stable Deployment first; remove the canary only after that rollout is Ready. The `x-canary: true` header remains a 100%-to-v2 QA override at every traffic weight.

After the interactive rollout accepts 100%, stage the tested canary image into the stable Minikube Helm values:
```powershell
.\platform-minikube.ps1 canary -Action promote -Namespace dev
```
Review and commit/push the resulting `helm/values/values-minikube.yaml` change to the GitOps branch. Wait until ArgoCD reports Synced/Healthy and the stable `products-service` Deployment is Ready on the same image. Only then remove the canary route and workload:
```powershell
.\platform-minikube.ps1 canary -Action retire -Namespace dev
```
The retirement command verifies the stable image and readiness before it removes the canary VirtualService, restores the baseline Istio DestinationRules, and deletes `products-service-v2`. To roll back before retirement, set traffic to `v1=100, v2=0`; after retirement, roll back by reverting the stable image tag through GitOps.

### 5. 🧪 Minikube MLOps Deployment & Automated Dynamic Training

`.\platform-minikube.ps1 up` automatically deploys MLflow, `demand-sales-capture`, and `demand-forecast-service` alongside dedicated ServiceAccounts (`mlflow-sa`, `demand-forecast-sa`, etc.) in the `dev` namespace:

```powershell
# Add or refresh MLOps on a running cluster:
.\platform-minikube.ps1 mlops

# Simulate and stream 14 calendar days of DELIVERED purchase orders into Kafka:
.\mlops\training.ps1 -Target minikube -SimulateOrders -Days 14
```

When simulating, the wrapper waits up to 180 seconds for the capture pod's automatic trainer and confirms a new run appears in MLflow. If none appears, it triggers the scheduler's guarded training Job and reports an error if no new run is recorded. Increase the initial wait with `-RunTimeoutSeconds 300` when needed. On success, the command prints the run name, ID, and a direct MLflow link. Minikube's UI is exposed at <http://localhost:5000>. Compose can run alongside it when bound to port 5001.

A shared `mlops-sales-data` PVC stores partitioned Parquet (`/data/sales_parquet/date=YYYY-MM-DD`). The `demand-model-training-scheduler` CronJob checks hourly, while the capture pod checks every 20 seconds. Both require at least 9 valid date partitions, a changed SHA-256 dataset fingerprint, and a 60-second stable Parquet snapshot before training. Runs log RMSE and MAE as MLflow metrics and enforce a dataset-scoped RMSE quality gate: runs that beat or match the active dataset's champion RMSE are promoted (`model_role=champion`, `promotion_status=PROMOTED|PROMOTED_INITIAL_BASELINE|PROMOTED_NEW_DATASET`) and served by `/api/forecast`, while non-improving runs are recorded as `model_role=challenger_rejected` (`promotion_status=REJECTED_BY_QUALITY_GATE`) in MLflow without replacing the active storefront model.

### 6. 🛑 Cluster Teardown, Pause & Fast Resume

```powershell
# 1. Stop and pause the Minikube cluster (preserves storage, database state, and volumes):
.\platform-minikube.ps1 down

# 2. Fast-resume the cluster in < 30 seconds (bypassing Terraform, Gatekeeper, and Helm packaging):
.\platform-minikube.ps1 start                       # Standard resume with Istio mesh
.\platform-minikube.ps1 start -WithoutIstio         # Fast resume in lightweight mode
.\platform-minikube.ps1 start -DeployCanary -CanaryImageTag v2.1  # Fast resume with canary
.\platform-minikube.ps1 up -Fast                    # Equivalent to start

# 3. Completely purge Minikube cluster, VM, volumes, and state:
.\platform-minikube.ps1 down -Destroy
```

### Useful commands

```powershell
# Check running microservices in the dev namespace
kubectl get pods -n dev # Or -A for all namespaces

# Check the keycloak startup
kubectl describe pod -l app=keycloak -n dev | Select-String -Pattern "Startup" -Context 2,10
```
```powershell
# 1. Orchestrated Vault Management (Automatic status, seed, rotate & init):
.\platform-minikube.ps1 vault -VaultAction status
.\platform-minikube.ps1 vault -VaultAction seed
.\platform-minikube.ps1 vault -VaultAction rotate

# 2. Direct CLI Inspection (Troubleshooting & Debugging):
# Via host Vault CLI (when port-forward or tunnel is active on localhost:8200):
$env:VAULT_ADDR = "http://localhost:8200"
$env:VAULT_TOKEN = "root"
vault kv get secret/products-service

# Via Minikube container exec:
kubectl exec -it -n vault deploy/vault -- vault kv get secret/products-service
kubectl exec -it -n vault deploy/vault -- vault policy list

# 3. Vault Agent Sidecar Injector Verification:
kubectl exec -it <pod-name> -n dev -c <app-container> -- cat /vault/secrets/database.env
kubectl logs <pod-name> -n dev -c vault-agent
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

    subgraph Autoscaling["⚖️ KEDA v2.21.0 & HPA Integration"]
        KEDA_OP[KEDA Operator v2.21.0<br/>Namespace: keda]
        SO_NOTIF[ScaledObject: notification-service<br/>Trigger: Kafka Lag & CPU]
        SO_GW[ScaledObject: cosmo-router<br/>Trigger: Prometheus RPS & CPU]
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

### 1. ⚖️ KEDA v2.21.0 Event-Driven Autoscaling & HPA Orchestration
* **Architecture & Coexistence:** KEDA does not replace Kubernetes `HorizontalPodAutoscaler` (HPA); it acts as an intelligent controller that creates and continuously synchronizes native `autoscaling/v2` HPA resources. To prevent flapping and replica race conditions, subcharts conditionally decouple native static HPAs when `keda.enabled=true`.
* **Kafka Consumer Lag Trigger (`notification-service`):** Scales pods dynamically in response to pending messages in the `orders-topic` partition queue (`lagThreshold: 10`), ensuring fast consumer drain under bulk checkout spikes.
* **Prometheus RPS Trigger (`cosmo-router`):** Evaluates real-time HTTP Request Per Second rates using PromQL (`sum(rate(router_http_requests_total{wg_subgraph_name=""}[1m]))`) scaling before CPU threshold saturation occurs.
* **CPU & Memory Stabilization:** ScaledObjects bundle resource utilization targets ($70\%$ CPU, $80\%$ Memory) alongside event triggers into a single unified HPA.
* **Zero-Downtime Guarantee (PDB):** Each microservice maintains `minAvailable: 1`, ensuring cluster upgrades, node drains, and evictions never compromise platform quorum.
* **2.21 migration note:** This release enforces service-account token audiences for Vault Kubernetes auth and `boundServiceAccountToken` scaler authentication. The project's current ScaledObjects use Kafka, Prometheus, CPU, and memory triggers without `TriggerAuthentication`/`ClusterTriggerAuthentication`, so no token-audience migration is needed for these manifests. If token-based KEDA authentication is added later, configure and verify the receiver's audience mappings before upgrading that environment. See the [KEDA 2.21 migration guide](https://keda.sh/docs/2.21/migration/).
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
* **Traffic Splitting:** Istio `VirtualService` (`products-service-canary-vs`) and `DestinationRule` (`products-service-dr`) allow guarded traffic shifting between stable `v1` and canary `v2` pods. `platform-minikube.ps1 canary -Action weight` validates replica readiness and a 100% total before patching weights.
* **Instant Header Bypass:** Requests containing header `x-canary: true` route $100\%$ to the canary subset regardless of percentage weight, enabling safe QA verification before public traffic exposure.
* **Interactive Progressive Rollout with Rollback:**
  ```powershell
  # Run the rollout gates in the namespace where the canary was deployed:
  .\platform-minikube.ps1 canary -Action rollout -Namespace dev -StepIntervalSeconds 30
  ```

### 4. 🚨 Alertmanager Alert Routing (Local Default, Slack & Jira Ready)
* **Prometheus Rule Discovery:** `helm/microservices-umbrella/templates/prometheus-rule.yaml` labeled with `release: kube-prometheus`, allowing the Prometheus Operator to automatically discover and monitor alerts (`ServiceDown`, `HighErrorRate`, `HighLatency`, `HighHeapUsage`, `RedisExporterDown`, `AlloyCollectorDown`). The Alloy alert covers both failed scrapes and a missing Alloy target.
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
