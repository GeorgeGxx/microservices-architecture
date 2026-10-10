# 🚇 Cloudflare Tunnels & DevSecOps Post-Deployment Verification

> [!TIP]
> 🧭 **[Enterprise Platform Hub](../../README.md)** > **02. Operations** > `CLOUDFLARE_TUNNELS.md`

This document details the architecture, configuration, and lifecycle management of **Cloudflare Quick Tunnels** integrated with the Minikube entrypoint to enable automated post-deployment verification in **GitHub Actions**.

---

## 🎯 1. Problem & Solution

### The Challenge
GitHub-hosted runners (`ubuntu-latest`) execute continuous integration pipelines in the cloud but **lack direct network visibility into your local workstation** (`localhost:5173`, `localhost:8080`, `localhost:8181`, or Minikube).

### The Solution
We leverage **Cloudflare Quick Tunnels** (`cloudflared tunnel --url http://localhost:...`) using the **HTTP/2** protocol:
1. Securely and ephemerally exposes local endpoints to public Anycast edge URLs (`https://*.trycloudflare.com`).
2. Automatically synchronizes the generated public URLs with the **Repository Variables** in GitHub Actions via `gh variable set`.
3. Enables the cloud-hosted `post-deployment-validation` job to execute the complete verification suite (DAST, SLO load tests, API contract tests, and smoke gates) against your local running stack.

```mermaid
flowchart LR
    subgraph GitHub Cloud ["☁️ GitHub Actions Runner (ubuntu-latest)"]
        Newman["🧪 Newman (API & Auth)"]
        Smoke["💨 Smoke Tests (smoke.py)"]
        K6["📈 k6 (SLO & Load)"]
        ZAP["🛡️ OWASP ZAP (DAST)"]
    end

    subgraph CF ["🛡️ Cloudflare Anycast Edge (*.trycloudflare.com)"]
        CF_FE["Frontend / API Ingress<br/>https://...trycloudflare.com"]
        CF_KC["Keycloak IAM<br/>https://...trycloudflare.com"]
    end

    subgraph Host ["💻 Local Workstation (Host Machine)"]
        CFTunnel["🚇 cloudflared daemon<br/>(HTTP/2 over TCP)"]
        
        subgraph Runtime ["Local Runtime Environment"]
            direction TB
            subgraph Compose ["Docker Compose"]
                C_FE["frontend: 5173"]
                C_GW["cosmo-router: 8080"]
                C_KC["keycloak: 8181"]
            end
            subgraph K8s ["Minikube + Istio Mesh"]
                K_TUN["supervise-tunnels.py<br/>(kubectl port-forward)"]
                K_FE["dev/frontend: 5173"]
                K_GW["dev/cosmo-router: 8080"]
                K_KC["auth/keycloak: 8181"]
            end
        end
    end

    Newman -->|OAuth2 / GraphQL / REST| CF_FE & CF_KC
    Smoke -->|/graphql & /healthz| CF_FE
    K6 -->|/api/product (SLO)| CF_FE
    ZAP -->|DAST Scan| CF_FE

    CF_FE --> CFTunnel
    CF_KC --> CFTunnel

    CFTunnel -->|5173, 8080, 8181| Compose
    CFTunnel -->|5173, 8080, 8181| K_TUN --> K8s
```

---

## ⚙️ 2. GitHub Actions Variables

The `post-deployment-validation` job defined in [`.github/workflows/_service-ci-cd-template.yml`](../../.github/workflows/_service-ci-cd-template.yml#L462-L521) consumes four variables (non-secret repository or environment variables):

| Variable | Scope | Purpose | Example with Cloudflare |
| :--- | :--- | :--- | :--- |
| `DEVSECOPS_POST_DEPLOY_ENABLED` | Repo / Env | Enables the job (`true`). When not `true`, GitHub skips the job. | `true` / `false` |
| `DEVSECOPS_BASE_URL` | Repo / Env | Gateway base URL for Newman, k6, and smoke tests. Targets unified Storefront reverse proxy (Nginx/Vite). | `https://automobile-...trycloudflare.com` |
| `DEVSECOPS_FRONTEND_URL` | Repo / Env | Public Storefront URL for OWASP ZAP baseline DAST and `smoke.py /healthz`. | `https://automobile-...trycloudflare.com` |
| `DEVSECOPS_KEYCLOAK_URL` | Repo / Env | Base URL of Keycloak (`microservices-realm`) for OAuth2 JWT tokens in Newman. | `https://pleased-...trycloudflare.com` |

> [!NOTE]
> Both `DEVSECOPS_BASE_URL` and `DEVSECOPS_FRONTEND_URL` point to the Storefront ingress (`:5173`). Its built-in Nginx/Vite reverse proxy routes all requests (`/graphql` to Cosmo Router, `/api/product` to Products, `/api/order` to Orders, and `/api/notifications` to Notifications).

---

## 🚀 3. Orchestration via the Minikube entrypoint

The Minikube entrypoint [`platform-minikube.ps1`](../../platform-minikube.ps1) delegates tunnel lifecycle tasks to [`scripts/manage-cloudflare-tunnels.ps1`](../../scripts/manage-cloudflare-tunnels.ps1):

### A. Start Tunnels & Synchronize GitHub Variables
```powershell
.\platform-minikube.ps1 cloudflare -Action start
```
1. Verifies local ports (`5173`, `8080`, `8181`) are actively listening.
2. Launches background `cloudflared` daemons with `--protocol http2` (preventing UDP/QUIC packet loss on local routers and Windows firewalls).
3. Waits for Anycast DNS propagation across Cloudflare edge nodes.
4. Verifies public HTTP 200 health responses for all three endpoints.
5. Invokes `gh variable set` on the repository to update all 4 variables.

### B. Inspect Status & Health
```powershell
.\platform-minikube.ps1 cloudflare -Action status
```
Outputs a table with active process IDs (PIDs), local target ports, edge health status, and live public URLs.

### C. Stop & Disable in CI
```powershell
.\platform-minikube.ps1 cloudflare -Action stop
```
Gracefully terminates `cloudflared` processes and sets `DEVSECOPS_POST_DEPLOY_ENABLED=false` in GitHub Actions to prevent CI pipelines from failing against closed tunnels.

### D. Restart
```powershell
.\platform-minikube.ps1 cloudflare -Action restart
```

---

## 🔄 4. Runtime Environments: Docker Compose vs. Minikube + Istio

| Feature | Docker Compose Environment | Minikube + Istio Service Mesh |
| :--- | :--- | :--- |
| **Startup Command** | `docker compose up -d` | `.\platform-minikube.ps1 up -WithIstio` |
| **Workload Location** | Containers in `spring` network | Pods in `dev`, `auth`, `data`, `istio-system` namespaces |
| **Network Security** | Docker bridge networks | Istio mTLS STRICT + Gatekeeper OPA policies |
| **Localhost Exposure** | Host port bindings (`5173`, `8080`, `8181`) | Supervised port-forwarding (`.\platform-minikube.ps1 tunnels`) or NodePort `30088` |
| **Cloudflare Ingress** | Direct binding to `http://localhost:...` | Direct binding to `http://localhost:...` via Minikube tunnel supervisor |

> [!IMPORTANT]
> **Seamless Compatibility:** Because [`scripts/supervise-tunnels.py`](../../scripts/supervise-tunnels.py) (`.\platform-minikube.ps1 tunnels`) forwards the exact same ports (`5173`, `8080`, `8181`) to the Istio ingress gateway, the Cloudflare tunnel manager (`.\platform-minikube.ps1 cloudflare -Action start`) **operates identically across both environments**.

---

## 🧪 5. Verified DevSecOps Suites

All testing technologies under `devsecops/` can be run through the Minikube entrypoint (which automatically handles environment variables and Docker volume binds) or manually via PowerShell:

### 1. Deployment Smoke Gates ([`scripts/testing/smoke.py`](../../scripts/testing/smoke.py))
* **Via Orchestrator:**
  ```powershell
  .\platform-minikube.ps1 smoke
  ```
* **Manual PowerShell Command:**
  ```powershell
  python scripts/testing/smoke.py --deployment --base-url "$env:BASE_URL" --frontend-url "$env:FRONTEND_URL"
  ```
* **Verification:**
  * Cosmo Router root GraphQL probe (`/graphql` -> `{"query": "{ __typename }"}`) -> HTTP 200.
  * Storefront Nginx health check probe (`/healthz`) -> HTTP 200.
  * Storefront index probe (`/`) -> HTTP 200.

### 2. Newman API Contracts & Auth Verification ([`microservices.postman_collection.json`](../../devsecops/testing/newman/microservices.postman_collection.json))
* **Via Orchestrator:**
  ```powershell
  .\platform-minikube.ps1 contract
  ```
* **Manual PowerShell Command:**
  ```powershell
  npx --yes newman@6 run devsecops/testing/newman/microservices.postman_collection.json --env-var "BASE_URL=$env:BASE_URL" --env-var "keycloak_url=$env:KEYCLOAK_URL" --bail
  ```
* **Test Coverage (20 requests, 47 assertions, 0 failures):**
  * `basic_user` / `password` -> JWT token generation and context propagation.
  * `admin_user` / `admin` -> Admin JWT token retrieval with `ROLE_ADMIN`.
  * Product catalog and federated subgraphs via Cosmo Router.
  * Order placement with DHL tracking format (`DHL-[A-Z0-9]+`) and `X-Idempotency-Key` validation.
  * Lifecycle state transitions: `PLACED` -> `SHIPPED` -> `DELIVERED`.
  * Saga pattern compensation on order cancellation with automated inventory rollback.
  * Funnel telemetry analytics intake (`/api/order/funnel`) -> HTTP 202.
  * Direct REST contingency endpoints (`/api/product`, `/api/inventory/in-stock`, `/api/order`).

### 3. Load Testing & SLO Gates with k6 ([`load-test.js`](../../devsecops/testing/k6/load-test.js))
* **Via Orchestrator:**
  ```powershell
  .\platform-minikube.ps1 performance
  ```
* **Manual PowerShell Command (Docker mount required):**
  ```powershell
  docker run --rm -v "${PWD}:/workspace:ro" grafana/k6:0.55.0 run --env "TARGET_URL=$env:BASE_URL" /workspace/devsecops/testing/k6/load-test.js
  ```
* **Results:**
  * 25 concurrent virtual users across a 25-second ramp.
  * p95 latency: **~167 - 204 ms** (SLO gate target: < 500 ms).
  * Rate-limiting tolerance confirmed: Nginx boundary rate limit (20 req/s per IP with burst of 30) returns HTTP 429 as designed, validating anti-DDoS defenses.

### 4. Dynamic Application Security Testing (DAST) with OWASP ZAP ([`rules.tsv`](../../devsecops/dast/zap/rules.tsv))
* **Via Orchestrator:**
  ```powershell
  .\platform-minikube.ps1 dast
  ```
* **Manual PowerShell Command (Docker mounts required):**
  ```powershell
  docker run --rm -v "${PWD}/devsecops/dast/zap:/zap/rules:ro" -v "${PWD}/devsecops/dast/zap:/zap/wrk:rw" ghcr.io/zaproxy/zaproxy:stable zap-baseline.py -t "$env:FRONTEND_URL" -c /zap/rules/rules.tsv -r zap-report.html -I
  ```
* **Results:**
  * 58 security scanning rules evaluated, 0 blocking vulnerabilities (`FAIL-NEW: 0`).
  * Interactive HTML report generated at `devsecops/dast/zap/zap-report.html`.

---

## 🛠️ 6. Troubleshooting & FAQ

### Why use `--protocol http2` instead of QUIC?
By default, `cloudflared` attempts QUIC connections (UDP port 7844). On Windows workstations and home Wi-Fi networks, certain routers and firewalls drop or throttle UDP packets towards Cloudflare Anycast edge servers. Enforcing `--protocol http2` switches to standard TCP-based TLS, ensuring a reliable, continuous handshake without silent disconnects.

### Does Keycloak reject requests if the tunnel URL changes?
No. The Keycloak instance is configured with:
* `KC_HOSTNAME_STRICT=false`
* `KC_PROXY_HEADERS=xforwarded`
* `KC_HTTP_ENABLED=true`
This allows Keycloak to serve requests from any dynamically generated `*.trycloudflare.com` domain without `Host` header rejections or issuer mismatches.
