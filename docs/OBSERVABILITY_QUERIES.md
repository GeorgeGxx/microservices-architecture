# 📊 Observability Query Handbook: PromQL, LogQL & TraceQL

> Complete reference and cheat sheet for telemetry queries used across the **Grafana LGTM Stack (Loki, Grafana, Tempo, Mimir/Prometheus)** and **OpenTelemetry** in the Enterprise Microservices Architecture.

---

## 🧭 Navigation & Service Endpoints

| Telemetry Engine | Local Endpoint | Default Port | Primary Function |
| :--- | :--- | :---: | :--- |
| **Grafana UI** | [http://localhost:3000](http://localhost:3000) | `3000` | Unified visualization, dashboards & Explore mode |
| **Prometheus** | [http://localhost:9090](http://localhost:9090) | `9090` | Timeseries metrics database & PromQL engine |
| **Grafana Loki** | [http://localhost:3100](http://localhost:3100) | `3100` | High-throughput centralized log indexing |
| **Grafana Tempo** | [http://localhost:3200](http://localhost:3200) | `3200` | Distributed tracing & OTLP span store |
| **OTel Collector** | `http://localhost:4317` (gRPC) / `4318` (HTTP) | `4317` / `4318` | OpenTelemetry telemetry ingestion pipeline |

---

## 📈 1. PromQL Queries (Prometheus & Micrometer 2.2.1)

PromQL (*Prometheus Query Language*) queries monitor golden signals, business conversion funnels, database connection pools, JVM performance, and security thresholds.

### 💼 E-Commerce Business Intelligence & Revenue KPIs

#### 📉 Cart Abandonment Rate (%)
Computes the percentage of shopping sessions that triggered cart additions but failed to complete checkout. Clamped between 0% and 100%.
```promql
clamp_max(clamp_min((1 - ((sum(ecommerce_orders{status="COMPLETED", service=~"$service"}) or sum(ecommerce_orders_total{status="COMPLETED", service=~"$service"}) or vector(0)) / clamp_min((sum(ecommerce_cart_additions_total) or vector(1)), 1))) * 100, 0), 100)
```

#### 💵 Net Sales Revenue (USD)
Total accumulated gross sales across all completed customer orders.
```promql
sum(ecommerce_revenue_usd{service=~"$service"}) or sum(ecommerce_revenue_usd_total{service=~"$service"}) or vector(0)
```

#### 🛍️ Completed Orders Count
Total count of orders that successfully reached `COMPLETED` / `DELIVERED` status.
```promql
sum(ecommerce_orders{status="COMPLETED", service=~"$service"}) or sum(ecommerce_orders_total{status="COMPLETED", service=~"$service"}) or vector(0)
```

#### 🏷️ Average Order Value (AOV)
Dynamic calculation: Total Sales Revenue $\div$ Total Completed Orders.
```promql
(sum(ecommerce_revenue_usd{service=~"$service"}) or sum(ecommerce_revenue_usd_total{service=~"$service"})) / clamp_min((sum(ecommerce_orders{status="COMPLETED", service=~"$service"}) or sum(ecommerce_orders_total{status="COMPLETED", service=~"$service"})), 1) or vector(0)
```

#### 🛒 4-Stage Conversion Funnel Metrics
Measures user progression through each e-commerce journey milestone:
```promql
# Stage 1: Cart Additions
sum(ecommerce_cart_additions_total) or vector(0)

# Stage 2: Checkout Initiated
sum(ecommerce_checkout_started_total) or vector(0)

# Stage 3: Payment Step Reached
sum(ecommerce_checkout_step_reached_total{step="PAYMENT"}) or vector(0)

# Stage 4: Order Completed
sum(ecommerce_orders{status="COMPLETED", service=~"$service"}) or sum(ecommerce_orders_total{status="COMPLETED", service=~"$service"}) or vector(0)
```

#### 🚚 5-Stage Logistics Pipeline Distribution
Counts live orders active across each fulfillment stage:
```promql
sum by (status) (ecommerce_orders_active_in_pipeline{service=~"$service"})
```
*Statuses:* `ORDER_PLACED`, `PREPARING_IN_HUB`, `IN_TRANSIT_DHL`, `OUT_FOR_DELIVERY`, `DELIVERED_AND_SIGNED`.

#### 📊 Live SKU Inventory & Low-Stock Detection
Reports instant warehouse stock quantity per product SKU.
```promql
ecommerce_inventory_sku_stock{service=~"$service"}
```

#### 🥧 Top-Selling SKUs & Catalog Market Share
Cumulative sales volume grouped by SKU.
```promql
sum by (sku) (ecommerce_sku_sales{service=~"$service"}) or sum by (sku) (ecommerce_sku_sales_total{service=~"$service"})
```

#### 👥 Customer Loyalty Cohort Retention
Orders distribution by loyalty tier (`NEW_USER`, `RETURNING`, `VIP`).
```promql
sum by (cohort) (ecommerce_orders_by_cohort{service=~"$service"})
```

---

### ⚡ Golden Signals: Traffic, Latency & Error Rates

#### 📈 Request Throughput (Requests Per Second - RPS)
Calculates per-second request rate grouped by service name and HTTP response code.
```promql
sum by (service, status) (rate(http_server_requests_seconds_count{service=~"$service"}[1m]))
```

#### ⏱️ P95 Request Latency by Microservice (in milliseconds)
Calculates 95th percentile response latency over a 5-minute rolling window:
```promql
histogram_quantile(0.95, sum by (le, service) (rate(http_server_requests_seconds_bucket{service=~"$service"}[5m]))) * 1000
```

#### ⏱️ P99 Critical Tail Latency (Global)
```promql
histogram_quantile(0.99, sum by (le) (rate(http_server_requests_seconds_bucket[5m]))) * 1000
```

#### 🚨 HTTP 5xx Server Error Spike Rate
```promql
sum by (service) (rate(http_server_requests_seconds_count{status=~"5.."}[1m]))
```

#### 🛑 Rate Limiter HTTP 429 Interceptions
Identifies clients or IPs throttled by API Gateway Redis token-bucket rate limiters:
```promql
sum(rate(http_server_requests_seconds_count{status="429"}[1m])) or vector(0)
```

---

### 🔄 Distributed Systems: Saga, Idempotency & Kafka

#### 🛡️ Idempotency Deduplication Hits
Number of duplicate requests intercepted via `X-Idempotency-Key`:
```promql
sum(ecommerce_idempotency_hits_total) or vector(0)
```

#### 🔄 Saga Compensations & Stock Restorations
Count of distributed transactions rolled back due to downstream inventory/payment failures:
```promql
sum(ecommerce_saga_compensations_total) or sum(ecommerce_compensations_total) or vector(0)
```

#### ⚡ Resilience4j Circuit Breaker Health Index
Returns 2 (Healthy/Closed), 1 (Half-Open), or 0 (Tripped/Open):
```promql
clamp_min(2 - 2 * (max(resilience4j_circuitbreaker_state{state="open"}) or vector(0)) - (max(resilience4j_circuitbreaker_state{state="half_open"}) or vector(0)), 0)
```

#### 📨 Kafka Event Publishing Throughput (Producer)
```promql
sum(rate(spring_kafka_template_seconds_count[1m])) or vector(0)
```

#### 📥 Kafka Notifications Processed Rate (Consumer)
```promql
sum by (status) (rate(notification_events_processed_total[1m]))
```

#### ⏳ Kafka Consumer Group Lag
Measures unconsumed messages pending in partitions:
```promql
sum by (topic, consumergroup) (kafka_consumergroup_lag)
```

---

### ☕ Platform & Infrastructure: JVM, Database & Cache

#### 🧠 JVM Heap Memory Usage (MB)
```promql
sum by (service) (jvm_memory_used_bytes{area="heap", service=~"$service"}) / 1048576
```

#### 🐘 HikariCP Active Database Connections vs Max Pool
Active connections currently in use by Spring Boot JPA repositories:
```promql
# Active Connections
sum by (service) (hikaricp_connections_active{service=~"$service"})

# Max Pool Size Configured
sum by (service) (hikaricp_connections_max{service=~"$service"})
```

#### ⚡ Redis Cache Hit Ratio (%)
```promql
sum(rate(redis_keyspace_hits_total[1m])) / (sum(rate(redis_keyspace_hits_total[1m])) + sum(rate(redis_keyspace_misses_total[1m]))) * 100
```

#### 🔐 HashiCorp Vault Core Unsealed Status
Returns `1` if Vault is initialized and unsealed; `0` if sealed.
```promql
vault_core_unsealed
```

#### 🛡️ Top 5 Blocked Attacker IPs
Identifies aggressive clients blacklisted by security rate limiters:
```promql
topk(5, sum by (ip) (security_blocked_ip_total)) or vector(0)
```

---

## 📜 2. LogQL Queries (Grafana Loki & Alloy v1.19.1)

LogQL (*Log Query Language*) allows searching, filtering, and calculating metrics over logs collected by Grafana Alloy from Docker containers and Kubernetes pods.

### 🔍 Real-Time Error Hunting & Exception Triage

#### 🚨 Global Microservices Error Stream
Streams all logs containing `ERROR` or Java stacktrace exceptions across all services:
```logql
{service=~".+"} |~ "(?i)ERROR|Exception"
```

#### 🎯 Service-Specific Error Isolation
Isolates errors originating specifically within `orders-service`:
```logql
{service="orders-service"} |~ "(?i)ERROR|Exception"
```

#### 🛡️ Security Audits & Malicious Traffic Logs
Filters logs for automated security interception alerts, rate-limit warnings, and blocked requests:
```logql
{service="api-gateway"} |~ "SECURITY-AUDIT|BLOCKED|RATE_LIMIT"
```

#### 🔄 Distributed Saga Compensation & Rollback Logs
Tracks Saga orchestrator compensation events when an order is cancelled or inventory fails:
```logql
{service="orders-service"} |~ "Saga compensation|Compensating order|Restoring inventory"
```

#### 📦 DHL Tracking Generation Logs
Finds order creation logs where tracking numbers are minted:
```logql
{service="orders-service"} |= "DHL Express" |= "trackingNumber"
```

---

### 🔗 Distributed Trace & Request Correlation

#### 🆔 Correlate Logs by Trace ID
Finds all logs generated across **all microservices** for a single end-to-end distributed transaction:
```logql
{service=~".+"} |= "<your-trace-id>"
```
> **Example:** `{service=~".+"} |= "4bf92f3577b34da6a3ce929d0e0e4736"`

#### 🌐 Correlate by Client IP or Customer Email
```logql
{service=~".+"} |= "admin_user@example.com"
```

---

### 📊 Log-to-Metrics Queries (Rate & Aggregations)

#### 📈 Error Log Velocity (Errors per Minute by Service)
Calculates per-minute frequency of errors to detect instant spikes:
```logql
sum by (service) (rate({service=~".+"} |= "ERROR" [1m]))
```

#### 🛑 Rate of Throttled Requests on API Gateway
```logql
sum(rate({service="api-gateway"} |= "429 Too Many Requests" [1m]))
```

#### 🧩 Structured JSON Field Unpacking & Status Filter
Parses structured JSON logs and filters requests where HTTP status $\ge 500$:
```logql
{service="api-gateway"} | json | status_code >= 500
```

---

### 🕸️ Service Mesh & Ingress Proxy Logs (Istio Envoy)

#### 🌐 Envoy Access Logs on API Gateway Pod
```logql
{container="istio-proxy", pod=~"api-gateway.+"}
```

#### ⏱️ Slow Ingress Requests via Envoy (> 200ms)
```logql
{container="istio-proxy"} | json | response_duration > 200
```

---

## 🔍 3. TraceQL Queries (Grafana Tempo 3.0.3 & OTel Tracing)

TraceQL (*Trace Query Language*) queries distributed traces collected by native Spring Boot OpenTelemetry exporters (`spring-boot-starter-opentelemetry`) and Tempo.

### ⏱️ Latency & Bottleneck Troubleshooting

#### 🐢 High-Latency Outlier Traces (> 500ms)
Locates traces where end-to-end request duration exceeded 500ms SLA:
```traceql
{ duration > 500ms }
```

#### 🚨 Extreme Bottlenecks (> 1.5s)
```traceql
{ duration > 1500ms }
```

#### 🐢 Slow Database Spans within PostgreSQL
Isolates slow SQL queries executed across microservices:
```traceql
{ span.db.system = "postgresql" && duration > 100ms }
```

---

### ❌ Error Tracing & Fault Localization

#### 💥 Traces with Unhandled Errors or HTTP $\ge$ 400
Locates all distributed spans that resulted in an error status or HTTP client/server fault:
```traceql
{ status = error || span.http.status_code >= 400 }
```

#### 🛑 Traces Intercepted with HTTP 429 Rate Limiting
```traceql
{ span.http.status_code = 429 }
```

#### 🔥 Gateway 504 Timeout or 503 Unavailable Traces
```traceql
{ span.http.status_code = 504 || span.http.status_code = 503 }
```

---

### 🌐 Cross-Service Topology & Multi-Span Cascades

#### 🔄 Multi-Hop Order Placement Journey
Locates traces that crossed both `api-gateway` and `orders-service`:
```traceql
{ resource.service.name = "api-gateway" } && { resource.service.name = "orders-service" }
```

#### 📦 Full End-to-End E-Commerce Chain (Gateway ➔ Orders ➔ Inventory)
Searches for traces spanning the complete multi-service synchronous checkout pipeline:
```traceql
{ resource.service.name = "api-gateway" } && { resource.service.name = "orders-service" } && { resource.service.name = "inventory-service" }
```

#### 📨 Asynchronous Kafka Messaging Traces
Finds traces where events were published to or consumed from Kafka topics:
```traceql
{ span.messaging.system = "kafka" }
```

#### 🔍 Traces Originating from Specific URL Endpoints
```traceql
{ span.http.route = "/api/order" && span.http.request.method = "POST" }
```

---

## 🛠️ Practical Quick-Reference Matrix

| Diagnostic Scenario | Recommended Tool | Query to Run |
| :--- | :---: | :--- |
| **High Cart Abandonment Alarm** | PromQL | `clamp_max(clamp_min((1 - ((sum(ecommerce_orders{status="COMPLETED"}) or vector(0)) / clamp_min((sum(ecommerce_cart_additions_total) or vector(1)), 1))) * 100, 0), 100)` |
| **Circuit Breaker Tripped** | PromQL | `resilience4j_circuitbreaker_state{state="open"}` |
| **Investigate Sudden 500 Error** | LogQL | `{service=~".+"} |~ "(?i)ERROR|Exception"` |
| **Trace a Customer Order by ID** | TraceQL | `{ span.http.route = "/api/order" && duration > 200ms }` |
| **Correlate Logs with a Trace** | LogQL | `{service=~".+"} \|= "<trace-id>"` |
| **Detect Database Pool Exhaustion**| PromQL | `hikaricp_connections_active / hikaricp_connections_max > 0.85` |
| **DDoS / Brute-force Attack** | PromQL | `sum(rate(http_server_requests_seconds_count{status="429"}[1m]))` |
| **Identify Top Attacking IP** | PromQL | `topk(5, sum by (ip) (security_blocked_ip_total))` |
