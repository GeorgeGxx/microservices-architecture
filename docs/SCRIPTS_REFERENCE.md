# 🛠️ Enterprise Automation Scripts & CLI Reference Manual

> Exhaustive reference manual for the unified platform CLI (platform.ps1), multi-cloud lifecycle scripts (AWS, Azure, GCP), OpenCost workload allocation, and platform operational tooling.

---

## 🚀 Enterprise Platform Unified CLI (`platform.ps1`)

The repository includes a single, master PowerShell orchestrator [`platform.ps1`](./platform.ps1) providing a standardized entrypoint for all platform operations across **4 target platforms** (`minikube`, `aws`, `azure`, `gcp`) and **3 environments** (`dev`, `staging`, `prod`):

```powershell
.\platform.ps1 <command> [-Platform minikube|aws|azure|gcp] [-Environment dev|staging|prod] [options]
```

### 📋 Complete Combinations Reference Guide

#### 1. 🚀 Bootstrap & Deployment (`up` / `bootstrap`)

| Platform | Command / Combination | Description & Effects |
| :--- | :--- | :--- |
| **Minikube** | `.\platform.ps1 up` | Default bootstrap: Minikube cluster, Istio Demo profile, Envoy sidecars, Gatekeeper OPA, Keycloak + `db-keycloak`, Vault, Data tier, Apps, Grafana/Prometheus, Tunnels & FinOps. |
| **Minikube** | `.\platform.ps1 up -Platform minikube -WithIstio` | Explicitly enables Istio service mesh, STRICT mTLS and Envoy proxy injection. |
| **Minikube** | `.\platform.ps1 up -Platform minikube -WithoutIstio` | Native Kubernetes mode without Envoy sidecars or Istio control plane overhead (saves 1.5 GB RAM). |
| **Minikube** | `.\platform.ps1 up -DeployCanary -CanaryImageTag <immutable-tag>` | Deploys a distinct products-service v2 image and starts at 90/10 stable/canary traffic. |
| **Minikube** | `.\platform.ps1 up -SkipScans` | Fast-track bootstrap: skips pre-flight Gitleaks, TFLint, Trivy, and Cosign validations. |
| **Minikube** | `.\platform.ps1 up -Cpus 8 -MemoryMb 8192 -DiskSize 50g` | Custom hardware allocation for lower-spec developer workstations. |
| **AWS** | `.\platform.ps1 up -Platform aws -Environment dev` | Deploys AWS Dev tier (corresponds to `develop` branch, namespace `dev`, burstable resources). |
| **AWS** | `.\platform.ps1 up -Platform aws -Environment staging` | Deploys AWS Staging tier (`staging` branch, namespace `staging`, medium performance: 2 replicas, 250m-500m CPU). |
| **AWS** | `.\platform.ps1 up -Platform aws -Environment prod` | Deploys AWS Production tier (`master` branch, namespace `production`, high performance HA: 3-10 replicas, ALB, Canary). |
| **AWS** | `.\platform.ps1 up -Platform aws -Environment <env> -AutoApprove` | Automated, non-interactive Terraform apply for CI/CD runners. |
| **Azure** | `.\platform.ps1 up -Platform azure -Environment dev` | Deploys Azure Dev tier (corresponds to `develop` branch, namespace `dev`, burstable B-series). |
| **Azure** | `.\platform.ps1 up -Platform azure -Environment staging` | Deploys Azure Staging tier (`staging` branch, namespace `staging`, medium performance D-series). |
| **Azure** | `.\platform.ps1 up -Platform azure -Environment prod` | Deploys Azure Production tier (`master` branch, namespace `production`, high performance HA, App Gateway). |
| **Azure** | `.\platform.ps1 up -Platform azure -Environment <env> -AutoApprove` | Automated non-interactive Terraform apply for Azure DevOps pipelines. |
| **GCP** | `.\platform.ps1 up -Platform gcp -Environment dev` | Deploys GCP Dev tier (corresponds to `develop` branch, namespace `dev`, e2-standard). |
| **GCP** | `.\platform.ps1 up -Platform gcp -Environment staging` | Deploys GCP Staging tier (`staging` branch, namespace `staging`, medium performance). |
| **GCP** | `.\platform.ps1 up -Platform gcp -Environment prod` | Deploys GCP Production tier (`master` branch, namespace `production`, high performance HA, Cloud Armor). |
| **GCP** | `.\platform.ps1 up -Platform gcp -Environment <env> -AutoApprove` | Automated non-interactive Terraform apply for Bitbucket Pipelines. |

---

#### 2. ⏸️ Teardown, Pause & Cluster Purge (`down` / `stop` / `destroy`)

| Command / Combination | Platform | Description & Effects |
| :--- | :--- | :--- |
| `.\platform.ps1 down` | Minikube | Gracefully terminates background tunnels and pauses Minikube. Preserves all container images, database data, and state. |
| `.\platform.ps1 down -Destroy` | Minikube | Deletes the Minikube VM/container, purges persistent volumes, and cleans local Terraform state. |
| `.\platform.ps1 destroy -Platform minikube` | Minikube | Direct alias for complete Minikube cluster and state purge. |
| `.\platform.ps1 down -Platform aws -Environment <dev\|staging\|prod>` | AWS | Runs `terraform destroy` against the specified AWS workspace. |
| `.\platform.ps1 destroy -Platform aws -Environment prod -AutoApprove` | AWS | Non-interactive purge of AWS production resources. |
| `.\platform.ps1 down -Platform azure -Environment <dev\|staging\|prod>` | Azure | Runs `terraform destroy` against the specified Azure workspace. |
| `.\platform.ps1 destroy -Platform azure -Environment prod -AutoApprove` | Azure | Non-interactive purge of Azure production resources. |
| `.\platform.ps1 down -Platform gcp -Environment <dev\|staging\|prod>` | GCP | Runs `terraform destroy` against the specified GCP workspace. |
| `.\platform.ps1 destroy -Platform gcp -Environment prod -AutoApprove` | GCP | Non-interactive purge of GCP production resources. |

---

#### 3. 📝 Terraform Infrastructure Planning & Apply (`plan` / `apply`)

| Command / Combination | Platform | Description & Effects |
| :--- | :--- | :--- |
| `.\platform.ps1 plan -Platform minikube` | Minikube | Generates the Graphviz visual dependency diagram (`docs/terraform-graph.png`). |
| `.\platform.ps1 plan -Platform aws -Environment <dev\|staging\|prod>` | AWS | Executes `terraform plan` for the selected AWS workspace and outputs plan file. |
| `.\platform.ps1 plan -Platform azure -Environment <dev\|staging\|prod>` | Azure | Executes `terraform plan` for the selected Azure workspace. |
| `.\platform.ps1 plan -Platform gcp -Environment <dev\|staging\|prod>` | GCP | Executes `terraform plan` for the selected GCP workspace. |
| `.\platform.ps1 apply -Platform aws -Environment staging -AutoApprove` | AWS | Provisions AWS staging infrastructure without interactive prompts. |
| `.\platform.ps1 apply -Platform azure -Environment prod -AutoApprove` | Azure | Provisions Azure production infrastructure without interactive prompts. |
| `.\platform.ps1 apply -Platform gcp -Environment dev -AutoApprove` | GCP | Provisions GCP dev infrastructure without interactive prompts. |

---

#### 4. 🔄 Automated Emergency Rollbacks (`rollback`)

| Command / Combination | Target | Recovery Action Performed |
| :--- | :--- | :--- |
| `.\platform.ps1 rollback` | Minikube | Rolls back the Helm umbrella release in namespace `dev` to the previous stable revision. |
| `.\platform.ps1 rollback -Platform aws -Environment staging` | AWS | Initiates emergency rollback: releases S3/DynamoDB state lock and triggers ArgoCD sync fallback. |
| `.\platform.ps1 rollback -Platform aws -Environment prod -LockId <ID>` | AWS | Forces release of a specific DynamoDB state lock (`terraform force-unlock <ID>`) and triggers rollback. |
| `.\platform.ps1 rollback -Platform azure -Environment staging` | Azure | Releases Azure Blob Storage state lease and triggers Helm rollback on AKS. |
| `.\platform.ps1 rollback -Platform azure -Environment prod -LockId <ID>` | Azure | Unlocks Azure Blob storage lease and executes production fallback. |
| `.\platform.ps1 rollback -Platform gcp -Environment staging` | GCP | Releases GCS state lock and executes GKE deployment rollback to previous replica revision. |
| `.\platform.ps1 rollback -Platform gcp -Environment prod -LockId <ID>` | GCP | Clears GCS state lock and triggers production rollback. |

---

#### 5. 🔍 Health Diagnostics & Verification (`doctor` / `verify` / `status`)

| Command / Combination | Target | Diagnostic Scope |
| :--- | :--- | :--- |
| `.\platform.ps1 doctor` | Minikube | Verifies pods across `dev`, `observability`, `auth`, `vault`, `data`, `argocd`, `gatekeeper-system`, active NodePorts, and runs synthetic OPA admission test. |
| `.\platform.ps1 doctor-minikube` | Minikube | Validates local Minikube + Istio Service Mesh installation, mTLS, control plane and mesh readiness. |
| `.\platform.ps1 doctor-cloud -Platform aws\|azure\|gcp` | Cloud | Validates multi-cloud Istio ingress gateway, mTLS policy, and microservice mesh routes. |
| `.\platform.ps1 doctor -Platform aws -Environment staging` | AWS | Inspects AWS EKS pod status, NLB / Istio ingress gateway, and IRSA bindings. |
| `.\platform.ps1 doctor -Platform azure -Environment prod` | Azure | Inspects Azure AKS pod status, Azure Front Door / Istio ingress gateway, and Workload Identity. |
| `.\platform.ps1 doctor -Platform gcp -Environment dev` | GCP | Inspects Google GKE pod status, Cloud Armor / Istio ingress gateway, and Workload Identity. |

---

#### 6. 💰 Live Kubernetes Costs and Offline Estimates (`cost` / `finops`)

| Command / Combination | Environment | Analysis Performed |
| :--- | :--- | :--- |
| `.\platform.ps1 cost` | Current Kubernetes context | Queries live namespace costs from OpenCost through Krew plugin `kubectl-cost` (`--opencost`). |
| `.\platform.ps1 finops -Environment minikube` | Local estimate | Runs the offline architecture estimate; it is not live cluster allocation or provider billing. |

---

#### 7. 🛠️ Host CLI Audit & Automated Winget Installation (`tools`)

| Command / Combination | Mode | Description |
| :--- | :--- | :--- |
| `.\platform.ps1 tools` | Audit Only | Fast audit checking presence and version of 18 documented project tools. |
| `.\platform.ps1 tools -Install` | Unattended Install | Automatically installs any missing tools via `winget install --id ... --silent --accept-package-agreements`. |

| `.\Install-DevTools.ps1` | Audit Only | Audits documented CLI/runtime tools; does not install packages by default. |
| `.\Install-DevTools.ps1 -Install` | Install Missing | Installs only documented WinGet packages. `-IncludeCloudCli` and `-InstallOpenCostPlugin` opt in to cloud CLIs/OpenCost Krew. |

---

#### 8. ⚡ Productivity, Security & Verification Utilities

| Command | Action Performed |
| :--- | :--- |
| `.\platform.ps1 urls` | Prints interactive colorized dashboard of active frontend, Cosmo Router, Keycloak IAM, Vault UI, Kiali, ArgoCD, Grafana, and Prometheus URLs with credentials. |
| `.\platform.ps1 smoke` | Executes automated synthetic integration smoke tests against the frontend, Cosmo Router GraphQL endpoint, and microservices. |
| `.\platform.ps1 tunnels` | Launches the resilient background port-forward supervisor daemon with automatic reconnection. |
| `.\platform.ps1 secrets [-Environment <dev\|staging\|prod>]` | Generates high-entropy CSPRNG cryptographic secrets (JWT keys, DB passwords, Keycloak client secrets) for Kubernetes manifests or `.env`. |
| `.\platform.ps1 security-scan` | Runs local pre-flight security suite: Gitleaks (secret detection), TFLint (Terraform static analysis), Trivy (chart/image vulnerabilities), and Cosign (signing validation). |
| `.\platform.ps1 graph` | Generates a visual Terraform dependency graph PNG at `docs/terraform-graph.png` using Graphviz (`dot`). |
| `.\platform.ps1 diagrams` | Synchronizes and programmatically regenerates all 12 architectural tabs in [`docs/Diagrams.drawio`](./Diagrams.drawio) via Python. |

---

## 🛡️ Cloud-Agnostic DevSecOps CLI Tooling (`platform.ps1` & `scripts/`)

The platform consolidates production-grade CLI tools for multi-cloud governance, disaster recovery, zero-trust credential bootstrapping, automated cluster provisioning, and observability lifecycle management across Minikube, AWS, Azure, and GCP.

All previously fragmented platform and cloud scripts (`manage-aws.ps1`, `manage-azure.ps1`, `manage-gcp.ps1`, `terraform-*.ps1`, `install-cli-tools.ps1`, `verify-platform.ps1`) have been **unified into the single master CLI [`platform.ps1`](../platform.ps1)**, eliminating script sprawl and ensuring 100% parameter symmetry across all target platforms.

| Tool | Location | Purpose | Key Capabilities | Runbook Command |
| :--- | :--- | :--- | :--- | :--- |
| **`platform.ps1`** | Root (`./platform.ps1`) | **Master Platform Orchestrator:** Unified lifecycle manager across Minikube, AWS, Azure, and GCP. | • Hardware sizing (6 CPUs, 12 GB RAM)<br/>• Multi-cloud bootstrap, plan, apply, destroy<br/>• Automated rollbacks & state unlocking<br/>• Health diagnostic audit (`doctor`) | `.\platform.ps1 up -Platform minikube` |
| **[`bootstrap-keycloak.ps1`](../scripts/bootstrap-keycloak.ps1)** | `scripts/` | **Keycloak 26 Realm & Client Bootstrapper:** Provisions IAM realm, roles, users, and clients. | • Syncs confidential client secret into `.env` and K8s<br/>• Configures public `microservices_frontend` for the SPA<br/>• Configures confidential `microservices_client` for automated tests | `pwsh -File .\scripts\bootstrap-keycloak.ps1` |
| **[`build-all.py`](../scripts/build-all.py)** | `scripts/` | **Multi-Threaded Container Image Compiler:** Concurrently builds all Java & React containers. | • Parallel compilation of 4 Spring Boot services<br/>• Nginx Distroless React 19 build<br/>• Docker daemon tagging & Minikube sync | `python scripts/build-all.py 1.0.0` |
| **[`endpoint-smoke-test.py`](../scripts/endpoint-smoke-test.py)** | `scripts/` | **Synthetic Post-Deployment Smoke Prober:** Independent gateway and frontend health/latency checks. | • Cosmo Router GraphQL (`/graphql`)<br/>• Frontend Nginx health (`/healthz`)<br/>• Frontend SPA root (`/`)<br/>• Separate gateway and frontend targets | `python scripts/endpoint-smoke-test.py --base-url http://localhost:8080 --frontend-url http://localhost:5173` |
| **[`generate-secure-secrets.py`](../scripts/generate-secure-secrets.py)** | `scripts/` | **Zero-Trust Cryptographic Secret Generator:** CSPRNG high-entropy key generator. | • High-entropy DB passwords and JWT keys<br/>• Exports to `.env`, JSON, or K8s `Secret` YAML<br/>• Automated HashiCorp Vault token generation | `python scripts/generate-secure-secrets.py --format k8s-yaml --namespace staging` |
| **[`local-cost-estimator.py`](../scripts/local-cost-estimator.py)** | `scripts/` | **Offline Architecture Estimate:** Illustrative profile totals, not live cloud cost data. | • Staging and production profile estimates<br/>• Not live provider billing<br/>• Clearly separate from OpenCost allocation | `python scripts/local-cost-estimator.py --env minikube` |
| **[`validate-opencost.sh`](../scripts/validate-opencost.sh)** | `scripts/` | Renders pinned OpenCost and cloud Prometheus Helm charts with project values in CI. | • Validates local and cloud values<br/>• Used by GitHub Actions, Azure DevOps, and Bitbucket | `bash scripts/validate-opencost.sh` |
| **[`supervise-tunnels.py`](../scripts/supervise-tunnels.py)** | `scripts/` | **Resilient Port-Forward Supervisor Daemon:** Background tunnel supervisor with auto-reconnect. | • Supervises frontend (5173), gateway (8080), keycloak (8181), vault (8200), grafana (3000), argo (8088)<br/>• Automatic recovery on transient network drops | `python scripts/supervise-tunnels.py` |
| **[`update_dashboards.py`](../scripts/update_dashboards.py)** | `scripts/` | **Grafana Dashboard Generator:** Writes the curated business and technical dashboard JSON. | • Local file generation is the default<br/>• Live publish requires `--push` plus `GRAFANA_TOKEN` or `GRAFANA_USERNAME` / `GRAFANA_PASSWORD`<br/>• Supports business and technical security panels | `python scripts/update_dashboards.py` (publish: `python scripts/update_dashboards.py --push`) |
| **[`generate_drawio.py`](../scripts/generate_drawio.py)** | `scripts/` | **Architectural Blueprint Generator:** Programmatically generates the 12-page Draw.io model. | • Generates [`docs/Diagrams.drawio`](./Diagrams.drawio)<br/>• 12 specialized architectural views<br/>• Mathematical layout without XML overlap | `python scripts/generate_drawio.py` |
| **`simulate.py`** | `scripts/testing/` | **Unified Load, Traffic, Checkout & GraphQL Flood Simulator.** | • Traffic/chaos use Cosmo Router; DDoS uses frontend edge via `DDOS_EDGE_URL` / `--ddos-url`<br/>• Keycloak JWT required unless DDoS `--no-auth` is explicit<br/>• Rate-limit probe reports real HTTP responses; Nginx JSON logs feed Loki IP panels<br/>• Stops before sending traffic/mutations if authentication fails | `python scripts/testing/simulate.py --scenario traffic` |
| **`smoke.py`** | `scripts/testing/` | **Frontend-to-Backend Smoke Tester:** Health, GraphQL, REST catalog/order, and security checks. | • Nginx health and Cosmo GraphQL<br/>• Catalog REST route through frontend<br/>• Authenticated and unauthenticated order routes | `python scripts/testing/smoke.py --base-url http://localhost:5173` |
| **`verify.py`** | `scripts/testing/` | **Component & Observability Verifier:** Audits Swagger, metrics, and dashboards. | • Validates Swagger UI and OpenAPI 3.0 specs<br/>• Queries Prometheus active metric series<br/>• Audits Grafana dashboards and datasource links | `python scripts/testing/verify.py --target all` |
| **`check.py`** | `scripts/testing/` | **Diagnostic Telemetry & PromQL Evaluator:** Probes JVM, cart abandonment, and Vault. | • JVM heap memory, threads, and CPU audit<br/>• Real-time cart abandonment PromQL audit<br/>• HashiCorp Vault seal status & telemetry probe | `python scripts/testing/check.py --check all` |
| **`test_order.py`** | `scripts/testing/` | **Authenticated Order-List Check:** Read-only REST check through frontend Nginx. | • Acquires a JWT from Keycloak with `microservices_client`<br/>• Uses `KEYCLOAK_CLIENT_SECRET` from environment or `.env`<br/>• Reads `GET /api/order`; does not create an order | `python scripts/testing/test_order.py` |

---

## 📂 Current Scripts Directory Structure (`scripts/`)

The repository maintains a clean, flat, and intuitive automation hierarchy:

```text
scripts/
├── testing/                           # Specialized enterprise testing and simulation suite
│   ├── check.py                       # Diagnostic telemetry & PromQL evaluator (JVM, Cart abandonment, Vault)
│   ├── simulate.py                    # GraphQL traffic, checkout, chaos, and flood scenarios
│   ├── smoke.py                       # Frontend, GraphQL, REST, and auth smoke checks
│   ├── test_order.py                  # Keycloak-authenticated read-only order-list check
│   └── verify.py                      # Component verifier for Swagger OpenAPI, Prometheus, and Grafana
├── bootstrap-keycloak.ps1             # Native PowerShell Keycloak 26 IAM realm bootstrapper & client secret sync
├── build-all.py                       # Concurrent multi-service container compiler (Java 21 Maven + React 19)
├── endpoint-smoke-test.py             # Standalone synthetic health, metrics, and security prober
├── generate-secure-secrets.py         # High-entropy CSPRNG credential & JWT generator
├── generate_drawio.py                 # Programmatic 12-page Draw.io architectural blueprint generator
├── local-cost-estimator.py            # Offline illustrative estimate (not provider billing)
├── validate-opencost.sh               # Render pinned OpenCost and cloud Prometheus charts
├── supervise-tunnels.py               # Resilient background port-forward supervisor daemon
└── update_dashboards.py               # Dashboard JSON generator; live Grafana publishing is opt-in
```

---

## 📖 Detailed Tooling Playbooks

### 1. 🔐 Keycloak IAM Bootstrap (`bootstrap-keycloak.ps1`)
Provisions `microservices-realm`, creates the public SPA client and confidential automation client, creates the local test users/roles, and writes the confidential client secret to `.env`. Run this after Keycloak is ready; Compose's `start-dev` command does not itself run this bootstrap:

```powershell
# Execute the native PowerShell Keycloak bootstrapper:
pwsh -File .\scripts\bootstrap-keycloak.ps1
```

### 2. 🔨 Concurrent Container Image Compiler (`build-all.py`)
Concurrently packages all 4 Spring Boot Java microservices (`products-service`, `orders-service`, `inventory-service`, `notification-service`) using Maven and compiles the React 19 frontend into optimized Distroless container images:

```powershell
# Build all images with tag 1.0.0:
python scripts/build-all.py 1.0.0
```

### 3. 🧪 Comprehensive Testing Suite (`scripts/testing/`)

#### A. Unified Simulation Engine (`simulate.py`)
Generates authenticated traffic, GraphQL load, and checkout chaos scenarios:

```powershell
# 1. Normal E-Commerce Traffic Simulation (JWT auth, browse, cart, order):
python scripts/testing/simulate.py --scenario traffic --orders 20 --concurrency 4

# 2. Continuous Shopping Flow:
python scripts/testing/simulate.py --scenario traffic --continuous

# 3. GraphQL flood through frontend Nginx shared edge limiter:
python scripts/testing/simulate.py --scenario ddos --duration 30 --workers 24 --distributed

# 4. GraphQL checkout validation (stock and invalid SKU responses):
python scripts/testing/simulate.py --scenario chaos --chaos-runs 20

# 5. Full Battery (Traffic + DDoS + Chaos):
python scripts/testing/simulate.py --scenario all
```
The scripts use `COSMO_ROUTER_URL` (default `http://127.0.0.1:8080`) for traffic/chaos and `DDOS_EDGE_URL` (default `FRONTEND_URL`, or `http://127.0.0.1:5173`) for the DDoS probe. Set `KEYCLOAK_CLIENT_SECRET` in the environment or `.env`; traffic and chaos stop without a token. DDoS also requires a token unless `--no-auth` is deliberately supplied. The shared frontend edge enforces 20 requests/second per observed socket peer with a burst of 30. Use at least 32 workers to reliably exercise the limiter on a local cluster; the simulator reports whether it actually observed HTTP 429 responses. Synthetic `X-Forwarded-For` values cannot bypass that limit or change the socket peer IP logged by Nginx. Alloy ships JSON 429 access records to Loki; the security panels use those actual events. On Minikube, `scripts/supervise-tunnels.py` forwards the Router, frontend, and Keycloak ports.

#### B. Unified Smoke Tester (`smoke.py`)
Validates frontend health, public GraphQL reachability, catalog REST, Keycloak token acquisition, authenticated order placement, and the negative unauthenticated order boundary:

```powershell
# Standard smoke test through frontend Nginx (GraphQL and proxied REST):
python scripts/testing/smoke.py

# Strict mode with custom latency threshold:
python scripts/testing/smoke.py --base-url http://localhost:5173 --max-latency-ms 300 --strict
```

#### C. Component & Observability Verifier (`verify.py`)
Verifies Swagger documentation, Prometheus metric exposition, and Grafana dashboards:

```powershell
# Validate all components:
python scripts/testing/verify.py --target all

# Validate specific targets:
python scripts/testing/verify.py --target swagger
python scripts/testing/verify.py --target metrics
python scripts/testing/verify.py --target grafana
```

#### D. Telemetry & PromQL Evaluator (`check.py`)
Directly checks JVM metrics, real-time cart abandonment ratios, and arbitrary PromQL queries:

```powershell
# Run all diagnostic checks:
python scripts/testing/check.py --check all

# Query JVM heap memory and GC statistics:
python scripts/testing/check.py --check jvm

# Query real-time cart abandonment calculation:
python scripts/testing/check.py --check abandonment

# Query Vault seal status:
python scripts/testing/check.py --check vault

# Execute arbitrary PromQL expression:
python scripts/testing/check.py --check promql --query "rate(http_server_requests_seconds_count[5m])"
```

### 4. 💰 Offline Architecture Estimate (`local-cost-estimator.py`)
Produces illustrative architecture profiles. It is neither live Kubernetes allocation nor actual AWS/Azure/GCP billing:

```powershell
# Local Minikube savings calculation:
python scripts/local-cost-estimator.py --env minikube

# Cloud environment cost breakdown:
python scripts/local-cost-estimator.py --env prod
```

### 5. 💰 Live Kubernetes Workload Cost (`kubectl-cost`)

Install the Krew plugin once and query OpenCost through the current kubeconfig context:

```powershell
kubectl krew install cost
kubectl cost namespace --opencost --show-all-resources --window 1d
kubectl cost deployment --opencost -A --window 1d
```

The Minikube UI is available at `http://localhost:7000`. Provider billing exports are not enabled by this workload-allocation phase.

### 6. 🚇 Background Tunnel Supervisor (`supervise-tunnels.py`)
Maintains resilient background port-forward connections for local development with automatic restart upon failure:

```powershell
# Launch tunnel supervisor:
python scripts/supervise-tunnels.py
```

### 7. 📐 Architectural Blueprint Generator (`generate_drawio.py`)
Programmatically regenerates the 12-page architectural diagram in [`docs/Diagrams.drawio`](./Diagrams.drawio) with full mathematical coordinate calculations:

```powershell
# Regenerate Draw.io diagram model:
python scripts/generate_drawio.py
```

---

### Progressive products-service canary lifecycle

- `scripts/istio/set-canary-weight.ps1` changes the v1/v2 split after checking Ready replicas and a 100% total.
- `scripts/istio/auto-canary-rollout.ps1` advances through interactive observation gates and restores the last accepted split on a declined/failed step.
- `scripts/istio/promote-canary.ps1 -Namespace dev` copies the 100%-validated canary image tag into Minikube Helm values. Review and push that change so ArgoCD deploys the stable workload.
- `scripts/istio/promote-canary.ps1 -Namespace dev -RetireCanary` verifies the stable Deployment runs that same Ready image, then removes the canary routing and workload.

Do not retire the canary until the GitOps promotion has synced and the stable Deployment is Ready. The tag must be immutable and the candidate must be the build that passed validation. When using `platform.ps1 up -Build -DeployCanary`, the existing products-service stable image is excluded from the local rebuild and image reload; the candidate is built under the unique supplied tag.
