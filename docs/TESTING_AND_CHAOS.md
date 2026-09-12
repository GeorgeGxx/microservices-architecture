# 🧪 Automated Testing, Load Simulation & Chaos Engineering Guide

> Practical execution handbook for synthetic shopper traffic, DDoS botnet simulation, Chaos fault injection, E2E smoke tests, and the Newman API test suite.

---

## 🧪 Automated Testing, Load Simulation & Chaos Engineering

Enterprise testing scripts located in `scripts/testing/`:

### 1. 🛒 Legitimate E-Commerce Traffic Generator (`simulate.py --scenario traffic`)
Simulates authentic shopping journeys: authenticates with Keycloak OIDC, browses catalog items, queries stock, places distributed purchase orders with idempotency UUIDs, cancels orders to exercise Saga compensation, and updates real-time Grafana business KPIs:

```powershell
# Run a quick batch of 15 orders with 3 worker threads:
python scripts/testing/simulate.py --scenario traffic

# Place custom number of orders with specified concurrency:
python scripts/testing/simulate.py --scenario traffic --orders 50 --concurrency 5

# Run continuous background shopper simulation:
python scripts/testing/simulate.py --scenario traffic --continuous
```

### 2. ⚡ Resilience4j Circuit Breaker State Verification
Test the automatic failure detection and self-healing lifecycle:
$$\text{🟢 CLOSED (Green)} \xrightarrow[\text{Failures}]{\text{Downstream outage}} \text{🔴 OPEN (Red, 15s window)} \xrightarrow[\text{15s timer}]{\text{Auto-recovery probe}} \text{🟡 HALF\_OPEN (Yellow)} \xrightarrow[\text{2 trial orders OK}]{\text{Health restored}} \text{🟢 CLOSED (Green)}$$

> [!NOTE]
> **Why Red only lasts 15 seconds:** `waitDurationInOpenState` is set to 15 seconds with `automaticTransitionFromOpenToHalfOpenEnabled: true`. Once tripped into **🔴 RED (`OPEN`)**, it will automatically transition to **🟡 YELLOW (`HALF_OPEN`)** after 15s of silence to test for backend recovery.

#### Step-by-Step Test Procedure:

##### 🔴 Step A: Trip Circuit Breaker into OPEN (Red `#ef4444`)
Simulate downstream outage by stopping `inventory-service` and generating continuous traffic so the Red state remains continuously visible on Grafana without expiring:
```powershell
# 1. Stop inventory dependency:
# For Docker Compose:
docker compose stop inventory-service

# For Kubernetes / Minikube:
kubectl scale deployment inventory-service --replicas=0 -n dev

# 2. Run continuous traffic to keep the circuit in steady OPEN (Red #ef4444):
python scripts/testing/simulate.py --scenario traffic --continuous
```
* **Grafana Verification:** The panel **⚡ Resilience4j Circuit Breakers Health** will display **`OPEN / TRIPPED` (🔴 Red)**.

---

##### 🟡 Step B: Observe Transition into HALF_OPEN (Yellow `#f59e0b`)
Pause incoming traffic for 15 seconds to allow Resilience4j's self-healing timer to transition into trial probe mode:
```powershell
# 1. Stop the continuous simulator in your terminal with: Ctrl + C

# 2. Wait 16 seconds (waitDurationInOpenState = 15s):
Start-Sleep -Seconds 16
```
* **Grafana Verification:** The panel automatically switches to **`HALF_OPEN / TESTING` (🟡 Yellow)**, awaiting 2 trial calls to evaluate backend health.

---

##### 🟢 Step C: Restore Backend Health and Return to CLOSED (Green `#10b981`)
Restart `inventory-service` and send 2 trial orders through the gateway to prove backend recovery:
```powershell
# 1. Restore the inventory microservice:
# For Docker Compose:
docker compose start inventory-service

# For Kubernetes / Minikube:
kubectl scale deployment inventory-service --replicas=1 -n dev

# 2. Send 2 trial orders (sequential concurrency) to satisfy the 2-call probe:
python scripts/testing/simulate.py --scenario traffic --orders 2 --concurrency 1
```
* **Grafana Verification:** Both trial orders succeed with HTTP 201, and the panel instantly resets to **`CLOSED / HEALTHY` (🟢 Green)**.


### 3. 💥 Chaos Engineering & Fault Injection (`simulate.py --scenario chaos`)
Injects artificial network latency and downstream HTTP 500 errors to validate fault tolerance and OpenTelemetry tracing:
```powershell
python scripts/testing/simulate.py --scenario chaos
```

### 4. 🛡️ DDoS & Rate Limiting Stress Attacks (`simulate.py --scenario ddos`)
Launches high-concurrency request floods against the API Gateway to trigger Redis Token Bucket rate limiting (HTTP 429) and activate the Security Threat Level gauge:
```powershell
# 1. Default: 30-second sustained flood with live terminal ticker (keeps Threat Level RED in Grafana):
python scripts/testing/simulate.py --scenario ddos

# 2. Custom sustained duration (e.g. 60 seconds):
python scripts/testing/simulate.py --scenario ddos --duration 60

# 3. Continuous flood (runs indefinitely until Ctrl + C):
python scripts/testing/simulate.py --scenario ddos --continuous

# 4. Instant fixed burst (300 requests):
python scripts/testing/simulate.py --scenario ddos --duration 10

# 5. Distributed botnet simulation (rotates 12 distinct attacker IP addresses):
python scripts/testing/simulate.py --scenario ddos --distributed

# 6. Anonymous attack without Keycloak authentication:
python scripts/testing/simulate.py --scenario ddos --no-auth
```

### 5. 🔍 Automated Smoke Tests & OpenAPI Auditing
```powershell
# Run automated HTTP smoke tests against all service endpoints:
python scripts/testing/smoke.py

# Verify OpenAPI v3 / Swagger docs availability:
python scripts/testing/verify.py --target swagger

# Verify Prometheus metrics & Grafana dashboards:
python scripts/testing/verify.py --target all
```

### 6. 📉 Cart Abandonment Rate KPI Verification & Testing
The **📉 Cart Abandonment Rate** panel in the **`🏢 Business Intelligence & Inventory Operations`** Grafana dashboard evaluates the proportion of buyer journeys where items were added to the shopping cart but never converted into finalized purchases:

$$\text{Cart Abandonment Rate (\%)} = \text{clamp}\left(\left(1 - \frac{\sum \text{Orders Completed}}{\sum \text{Cart Additions}}\right) \times 100,\, 0,\, 100\right)$$

* **🟢 0% – 50% (Green):** High sales conversion efficiency (healthy e-commerce funnel).
* **🟡 50% – 75% (Yellow):** Moderate abandonment indicating checkout friction or drop-off.
* **🔴 75% – 100% (Red):** Critical commercial warning (high drop-off rate, uncompleted purchases).

#### Step-by-Step Testing Procedures (3 Verified Methods):

##### 🚀 Method 1: Instant CLI / PowerShell Event Injection (Simulate Mass Abandonment)
Rapidly pump asynchronous "Cart Addition" funnel telemetry events (`CART_ADD`) without completing checkouts:

```powershell
# Inject 30 abandoned cart events via the public Orders Funnel API:
1..30 | ForEach-Object {
    Invoke-RestMethod -Uri "http://localhost:8080/api/order/funnel" `
      -Method POST `
      -ContentType "application/json" `
      -Body '{"eventType":"CART_ADD","category":"Electronics"}'
}
```

* **Grafana Verification:** Open **http://localhost:3000** &rarr; Dashboards &rarr; **`🏢 Business Intelligence & Inventory Operations`**.
* The **`📉 Cart Abandonment Rate`** gauge instantly spikes into the **🟡 Yellow** / **🔴 Red** zone (~70% – 85%), reflecting the sudden drop in conversion.

---

##### 🖥️ Method 2: Interactive Browser Testing via Angular Frontend SPA
1. Open the storefront in your web browser: **[http://localhost:4200](http://localhost:4200)**.
2. Browse the product catalog and click **"Add to Cart"** repeatedly on various items without proceeding to checkout (each button click emits a real-time `CART_ADD` telemetry event to `orders-service`).
3. Leave the session idle or close the shopping cart drawer (abandoning the purchase).
4. Refresh the **`🏢 Business Intelligence & Inventory Operations`** dashboard in Grafana to observe the gauge needle climb upward.
5. Next, proceed through the checkout flow and click **"Place Order & Pay"**: once the order completes with `HTTP 201 Created`, the gauge needle immediately swings back down toward the **🟢 Green** zone.

---

##### ⚡ Method 3: Multi-Threaded Realistic Funnel Generation (`simulate.py --scenario traffic`)
Run the autonomous e-commerce load generator to exercise the complete funnel stages (`CART_ADD` $\rightarrow$ `CHECKOUT_START` $\rightarrow$ `CHECKOUT_STEP` $\rightarrow$ `PLACED` $\rightarrow$ `DELIVERED`):

```powershell
# Simulate 20 realistic shopper journeys with 4 parallel threads:
python scripts/testing/simulate.py --scenario traffic --orders 20 --concurrency 4
```

* **Behavior:** The script realistically blends abandoned carts, partial checkouts, completed purchases, and Saga cancellations, dynamically balancing the abandonment metric in real time.

### 📦 Postman & Newman Test Suite (Unified Collection):
The repository maintains a single, comprehensive Postman collection in [`devsecops/testing/newman/microservices.postman_collection.json`](./devsecops/testing/newman/microservices.postman_collection.json) containing all **22 verified requests** designed for both interactive desktop usage in Postman and headless automated CI/CD pipeline execution with Newman:

* **Zero-Config 1-Click Authentication:** Run `🔑 Authentication ➔ 1. Login as Admin` to fetch and store the JWT into `{{jwt_token}}` via Keycloak's public client (`microservices_frontend`). **No `client_secret` required!**
* **Dynamic Chaining (`{{order_id}}`):** Creating an order automatically saves its ID into collection variables, allowing `Cancel Order`, `Ship Order`, and `Deliver Order` to run sequentially without manual edits.
* **E-Commerce Scenarios:** Includes pre-built JSON payloads for **Automated DHL Tracking Generation** (`POST /api/order`), **Cart Abandonment Rate** funnel events (`POST /api/order/funnel`), multi-currency catalog creation (`POST /api/product`), and real-time SSE notifications stream (`GET /api/notifications/stream`).
* **CI/CD Quality Gate (Newman CLI):** Fully compatible with automated pipeline execution in GitHub Actions, Azure DevOps, and Bitbucket Pipelines (`newman run $COLLECTION --env-var "BASE_URL=${TARGET_URL}"`). Pre-request scripts automatically harmonize `base_url` and `BASE_URL`.

---

