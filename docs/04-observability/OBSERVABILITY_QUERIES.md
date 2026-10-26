# 📊 Observability Query Handbook: PromQL, LogQL & TraceQL

> [!TIP]
> 🧭 **[Enterprise Platform Hub](../../README.md)** > **04. Observability** > `OBSERVABILITY_QUERIES.md`

> Reference for queries used with the project's actual Grafana datasources (Prometheus, Loki, and Tempo) and its telemetry collectors (Grafana Alloy and OpenTelemetry Collector).

---

## 🧭 Navigation & Observability Service Endpoints

For the complete catalog of infrastructure ports, credentials, and telemetry ingress routing across Docker Compose and Minikube environments, refer to the canonical [Unified Endpoints, API Routing & Swagger Access Matrix](../01-architecture/ARCHITECTURE.md#-unified-endpoints-api-routing--swagger-access-matrix) and [Workload Matrix, Infrastructure Sizing & Cloud Target Mapping](../01-architecture/ARCHITECTURE.md#-workload-matrix-infrastructure-sizing--cloud-target-mapping) in `ARCHITECTURE.md`. Grafana queries data from Prometheus, Loki, and Tempo; Alloy collects container/pod logs and ships them to Loki; the OpenTelemetry Collector forwards traces to Tempo. For Docker Compose the datasource URLs are service DNS names (`prometheus:9090`, `loki:3100`, `tempo:3200`). In Minikube, Grafana uses the Kubernetes service URLs provisioned in `k8s/minikube/infra/grafana-datasources.yaml`.

---

## 📈 1. PromQL Queries (Prometheus & Micrometer 2.2.1)

PromQL (*Prometheus Query Language*) queries monitor golden signals, business conversion funnels, database connection pools, JVM performance, and security thresholds.

### Availability SLO and Error Budget

The initial service objective is **99.5% successful HTTP requests** for the four Spring services, excluding Actuator endpoints. The paired 5-minute and 1-hour alert fires when both 5xx ratios exceed 7.2% (14.4x burn against the 0.5% error budget). This is an early operational objective, not a customer contract; review it against measured traffic before production adoption. Low or absent traffic produces no ratio series and is handled separately by target availability alerts.

```promql
# Current per-service 5xx ratio (5-minute window)
microservices:http_error_ratio:rate5m

# Remaining error-budget burn condition used by the alert
(microservices:http_error_ratio:rate5m > 0.072)
and
(microservices:http_error_ratio:rate1h > 0.072)
```

The alert includes the `slo="availability"` and `objective="99.5%"` labels and a repository runbook pointer. The recording rules are installed for Docker Compose, Minikube Prometheus, and the Kubernetes PrometheusRule chart.

### 💼 E-Commerce Business Intelligence & Revenue KPIs

#### 🛒 Observed Funnel Event Activity (selected range)
The Orders Service exports process-local counters for events it actually receives. Events are not correlated by shopper/session, and completed orders are a database-backed gauge, so these counts cannot be interpreted as a conversion or cart-abandonment rate. Event counters reset when Orders Service restarts.
```promql
sum(increase(ecommerce_funnel_events_total{event_type="cart_add"}[$__range])) or vector(0)
sum(increase(ecommerce_funnel_events_total{event_type="checkout_start"}[$__range])) or vector(0)
sum(increase(ecommerce_funnel_events_total{event_type="checkout_step",step="PAYMENT"}[$__range])) or vector(0)
sum(max by (service) (clamp_min(delta(ecommerce_orders{status="COMPLETED",service="orders-service"}[$__range]), 0))) or vector(0)
```

#### 💵 Delivered Merchandise Value (USD)
All-time database-backed merchandise value from delivered orders. Tax, shipping, and cancelled orders are excluded. Use `max`, not `sum`, because replicas export the same database total.
```promql
max(ecommerce_revenue_usd{service="orders-service"})
```

#### 🛍️ Delivered Orders Count
All-time database-backed delivered-order snapshot, deduplicated across replicas. The Prometheus status label remains `COMPLETED` for compatibility with the existing metric contract.
```promql
max(ecommerce_orders{status="COMPLETED", service="orders-service"})
```

#### 🏷️ Merchandise Value per Delivered Order
All-time merchandise value divided by delivered-order count; tax, shipping, and cancelled orders are excluded.
```promql
max(ecommerce_revenue_usd{service="orders-service"}) / clamp_min(max(ecommerce_orders{status="COMPLETED",service="orders-service"}), 1)
```

#### 📈 Delivered Merchandise and Order Change (5-Minute Window)
Each point reports the observed change across the preceding five minutes. This window remains longer than the 15-second scrape interval even when Grafana's graph step is small; a stable snapshot returns zero.
```promql
max by (service) (delta(ecommerce_orders{status="COMPLETED",service="orders-service"}[5m]))
max by (service) (delta(ecommerce_revenue_usd{service="orders-service"}[5m]))
```

#### 🧾 All-Time Cancelled Orders
Current database-backed cancelled-order snapshot, deduplicated across replicas.
```promql
max(ecommerce_orders{status="CANCELLED",service="orders-service"})
```

#### 🛒 Observed Funnel Event Counts
Counts actual event increments over the selected time range. Since events do not carry a shared session identifier, these metrics cannot establish user progression or abandonment:
```promql
sum(increase(ecommerce_funnel_events_total{event_type="cart_add"}[$__range])) or vector(0)
sum(increase(ecommerce_funnel_events_total{event_type="checkout_start"}[$__range])) or vector(0)
sum(increase(ecommerce_funnel_events_total{event_type="checkout_step",step="PAYMENT"}[$__range])) or vector(0)
```
#### 🚚 Current Orders by Fulfillment Status
Current non-cancelled order counts by persisted status. `DELIVERED` is a terminal state and is shown for reporting. `max by (status)` prevents shared database snapshots from being counted once per service replica.
```promql
max by (status) (ecommerce_orders_active_in_pipeline)
```

#### 📊 Live SKU Inventory & Low-Stock Detection
Reports instant warehouse stock quantity per product SKU.
```promql
max by (sku) (ecommerce_inventory_sku_stock{service=~"$service"})
```
The inventory gauge is exported by each Inventory Service replica, so raw series repeat a SKU with different `pod`/`instance` labels. Aggregate by `sku` in Grafana to render one bar per product instead of one per replica.

#### 🥧 All-Time Delivered Units by SKU
All-time units sold in delivered orders grouped by SKU. Use `max` so a shared database snapshot is not counted once per replica.
```promql
max by (sku) (ecommerce_sku_sales{service="orders-service"})
```

#### 👥 Customer Loyalty Cohort Retention
Delivered orders distribution by loyalty tier (`first_time`, `repeat`, `loyal_vip`).
```promql
sum by (cohort) (ecommerce_orders_by_cohort{service=~"$service"})
```

---

### ⚡ Golden Signals: Traffic, Latency & Error Rates (Unified Router & Subgraphs)

#### 📈 Request Throughput (Requests Per Second - RPS)
Calculates per-second request rate across both Cosmo Router (GraphQL) and Spring Boot subgraphs:
```promql
# Unified (Cosmo Router + Spring Boot Subgraphs):
sum by (service, status) (rate(http_server_requests_seconds_count{service=~"$service"}[1m])) 
or 
sum by (service, http_status_code) (rate(router_http_requests_total{service=~"$service",wg_subgraph_name=""}[1m]))
```

#### ⏱️ P95 Request Latency by Microservice (in milliseconds)
Calculates 95th percentile response latency over a 5-minute rolling window:
```promql
# Subgraphs (Spring Boot):
histogram_quantile(0.95, sum by (le, service) (rate(http_server_requests_seconds_bucket{service=~"$service"}[5m]))) * 1000

# Edge Gateway (Cosmo Router):
histogram_quantile(0.95, sum by (le) (rate(router_http_request_duration_milliseconds_bucket{wg_subgraph_name=""}[5m])))
```

#### ⏱️ P99 Critical Tail Latency (Global Gateway)
```promql
histogram_quantile(0.99, sum by (le) (rate(router_http_request_duration_milliseconds_bucket{wg_subgraph_name=""}[5m])))
or
(histogram_quantile(0.99, sum by (le) (rate(http_server_requests_seconds_bucket[5m]))) * 1000)
```

#### 🚨 HTTP 5xx Server Error Spike Rate
```promql
sum by (service) (rate(http_server_requests_seconds_count{status=~"5.."}[1m]))
or
sum by (service) (rate(router_http_requests_error_total{wg_subgraph_name="",http_status_code=~"5.."}[1m]))
```

#### 🛑 Frontend Nginx Rate-Limit HTTP 429 Interceptions
The shared Compose/Minikube edge returns HTTP 429 after the per-peer token bucket is exceeded. Alloy ships the frontend JSON access log to Loki:
```logql
sum(rate({service="frontend"} | json | __error__="" | status=429 [1m])) or vector(0)
```
The `Edge Security Attack Status & Threat Level` Stat panel uses this rate with
value thresholds: green below 1 blocked request/sec, amber from 1/sec, and red
from 5/sec. It intentionally relies on thresholds (without range value
mappings) so the background color reflects the current value.

---

### 🚀 Cosmo Router & Federation 2.3 Supergraph Telemetry (Go Engine)

#### 🧩 Query Planning Latency (P95 in ms)
Measures the duration Cosmo Router takes in its Go runtime to compute the distributed query execution plan across subgraphs:
```promql
histogram_quantile(0.95, sum by (le) (rate(router_graphql_operation_planning_time_milliseconds_bucket[5m])))
```

#### 📦 Subgraph Request Throughput & Decomposition
HTTP requests dispatched by Cosmo Router, grouped by the downstream address. This uses the Router's OpenTelemetry HTTP client instrument; confirm that instrument is enabled in the Router metrics exporter before relying on it:
```promql
sum by (wg_subgraph_name) (rate(router_http_requests_total{wg_subgraph_name!=""}[1m]))
```

#### ⏱️ Downstream HTTP P95 Latency
Shows downstream HTTP latency grouped by server address; the address is not guaranteed to map one-to-one to a named subgraph:
```promql
histogram_quantile(0.95, sum by (le, wg_subgraph_name) (rate(router_http_client_time_to_first_byte_milliseconds_bucket[5m])))
```

#### ❌ GraphQL Operation Errors Rate
Tracks GraphQL field-level or execution errors returned by Cosmo Router:
```promql
sum by (http_status_code) (rate(router_http_requests_error_total{wg_subgraph_name=""}[1m]))
```

#### 🦀 Cosmo Router Connections & Active Requests
Router v2 exposes open connections and active HTTP requests (the old session-count metric is deprecated):
```promql
# In-flight HTTP requests:
router_http_requests_in_flight{wg_subgraph_name=""}

# Open client connections:
router_http_client_connection_active
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

### 🧪 MLOps & Demand Forecasting Telemetry (FastAPI & PySpark)

The Demand Forecast service (`demand-forecast-service`) exposes Prometheus metrics on port `8005` using the Prometheus Python client. Dashboard views are split by audience: API availability, request rate, latency, and SLO impact are in **Microservices Architecture · Technical & Security Operations (SRE)**; sales-data freshness, active-model age, and RMSE/MAE are in **E-Commerce Business Intelligence & Inventory Operations**. MLflow remains the source for full experiment and model-registry details.

#### 🟢 Forecast API Availability
Monitors runtime liveness of the FastAPI prediction server:
```promql
max(up{service="demand-forecast-service"}) or vector(0)
```

#### ⏱️ Age of Latest Successful Forecast (Hours)
Measures how long it has been since the API returned a successful forecast. This is shown with business inventory indicators:
```promql
(time() - max(demand_forecast_last_success_unixtime{service="demand-forecast-service"})) / 3600
```

#### 📅 Age of Latest Observed Sales Date (Days)
Evaluates freshness of the sales data consumed by the forecasting model:
```promql
(time() - max(demand_forecast_last_observed_sale_unixtime{service="demand-forecast-service"})) / 86400
```

#### ⚡ Forecast API Request Throughput (Requests/Minute)
The technical dashboard includes forecast traffic in the shared per-service HTTP throughput panel. Health checks are excluded:
```promql
sum(rate(demand_forecast_http_requests_total{service="demand-forecast-service",path!="/health"}[5m])) * 60
```

#### ⏱️ Forecast API Request Latency P95 (Milliseconds)
The technical dashboard adds this series to the per-service P95 panel. Health checks are excluded so frequent probes do not hide slower forecast requests:
```promql
histogram_quantile(0.95, sum by (le) (rate(demand_forecast_http_request_duration_seconds_bucket{service="demand-forecast-service",path!="/health"}[5m]))) * 1000
```

#### ❌ Forecast API 5xx Ratio and SLO Burn
The SRE dashboard includes this ratio in the single worst-service availability SLO burn value. Health checks are excluded; available services without request traffic contribute zero burn:
```promql
(
  sum by (service) (rate(demand_forecast_http_requests_total{service="demand-forecast-service",path!="/health",status=~"5.."}[5m]))
  or on (service) (max by (service) (up{service="demand-forecast-service"} == 1) * 0)
)
/
clamp_min(sum by (service) (rate(demand_forecast_http_requests_total{service="demand-forecast-service",path!="/health"}[5m])), 1e-9)
```

#### 🎯 Model Evaluation Metrics: RMSE & MAE
Tracks prediction quality recorded by the active MLflow-trained model:
```promql
# Active Model RMSE (shown in its own dashboard stat)
max(demand_forecast_model_rmse{service="demand-forecast-service"})

# Active Model MAE (shown in its own dashboard stat)
max(demand_forecast_model_mae{service="demand-forecast-service"})
```

#### ⌛ Active Model Age (Hours Since Training)
Tracks age of the model currently served by the forecast API:
```promql
max(demand_forecast_model_age_seconds{service="demand-forecast-service"}) / 3600
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

#### 🛡️ Top 5 Blocked Peer IPs
Ranks the socket peer addresses observed by Nginx for responses it rejected. Caller-controlled `X-Forwarded-For` is not used as the limiter key; behind another proxy, the peer may be that proxy rather than the original user:
```logql
topk(5, sum by (peer_ip) (count_over_time({service="frontend"} | json | __error__="" | status=429 | peer_ip!="" [15m]))) or on() label_replace(vector(0), "peer_ip", "No blocked peers", "__name__", ".*")
```
The dashboard's blocked-request count uses the same JSON parse-error filter
over a 15-minute window. With no matching events, the peer-IP query returns a
`No blocked peers` series instead of an empty result. Run the authenticated
`simulate.py --scenario ddos` against the local frontend edge to produce real
Nginx 429 logs; synthetic `X-Forwarded-For` values do not create separate
### ⚡ Grafana Alloy Collector Telemetry & Pipeline Health

#### 🟢 Alloy Collector Daemon Uptime & Health
Verifies that the Grafana Alloy daemon target is scraped successfully by Prometheus TSDB:
```promql
up{job="alloy"}
```
The `AlloyCollectorDown` alert fires when a scrape fails or when the Alloy target disappears from Prometheus service discovery. In Minikube, Alloy's per-node storage directory persists its file-source offsets across pod replacement while the node disk remains; it is local to Minikube and is not a backup across cluster deletion. Compose uses the named `alloy_data` volume.

#### 🔄 Alloy Restarts in the Last 24 Hours
Prefer Kubernetes' exact container restart counter when kube-state-metrics is available. Docker Compose does not expose that series, so the dashboard falls back to changes in Alloy's Prometheus process start-time metric:
```promql
sum(increase(kube_pod_container_status_restarts_total{namespace="observability",container="alloy"}[24h]))
or sum(changes(process_start_time_seconds{job="alloy"}[24h]))
```
The Compose fallback requires a stable `job="alloy"` scrape target and at least two samples. It counts observed Alloy process restarts, not Docker's historical container restart counter.

#### ⚙️ Pipeline Components Controller Health
Total active pipeline components in `healthy` status managed by Alloy controller:
```promql
sum(alloy_component_controller_running_components{job="alloy", health_type="healthy"})
```

#### 💻 Alloy CPU Consumption
CPU cores currently consumed by the busiest Alloy instance (process CPU time, not percentage of the container limit):
```promql
max(rate(process_cpu_seconds_total{job="alloy"}[5m]))
```

#### 🧠 Alloy Resident Memory (RSS) vs Container Limit (256MB)
Monitors real memory consumption against the 256MB Docker/Kubernetes boundary:
```promql
process_resident_memory_bytes{job="alloy"}
```

#### 📥 Entries Sent to Loki (entries/second)
Tracks entries Alloy reports as sent to Loki. This is collector-side delivery throughput, not a guarantee of end-to-end indexing latency:
```promql
sum(rate(loki_write_sent_entries_total{job="alloy"}[5m]))
```

#### ⏱️ Loki Push Request Duration (P95, milliseconds)
Estimates the P95 HTTP push request duration from Alloy to Loki. It does not measure end-to-end ingestion latency. No request observations produce no data:
```promql
(histogram_quantile(0.95, sum by (le) (rate(loki_write_request_duration_seconds_bucket{job="alloy"}[5m]))) * 1000)
and (sum(rate(loki_write_request_duration_seconds_count{job="alloy"}[5m])) > 0)
```

#### ⚠️ Alloy Delivery Retries, Dropped Entries & Parse Errors
These are separate counter rates; an absent series is shown as no data rather than being presented as zero:
```promql
sum(rate(loki_write_batch_retries_total{job="alloy"}[5m]))
sum(rate(loki_write_dropped_entries_total{job="alloy"}[5m]))
sum(rate(loki_source_docker_target_parsing_errors_total{job="alloy"}[5m]))
```

---

## 📜 2. LogQL Queries (Grafana Loki & Alloy v1.21.0)

LogQL (*Log Query Language*) allows searching, filtering, and calculating metrics over logs collected by Grafana Alloy from Docker containers and Kubernetes pods. Alloy's pipeline includes multiline exception aggregation (`stage.multiline`) and structured JSON parsing (`stage.json`), promoting `level` to an indexed label without elevating cardinality.

### 🔍 Real-Time Error Hunting & Exception Triage

#### 🎯 High-Performance Indexed Error Filter (via Alloy `level` label)
Queries Loki using the indexed `level` label promoted by Alloy pipeline stages:
```logql
{service=~".+", level=~"(?i)ERROR|FATAL"}
```

#### 🚨 Global Microservices Error Stream (Text & Regex)
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
{service="cosmo-router"} |~ "SECURITY-AUDIT|BLOCKED|RATE_LIMIT"
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

#### 🛑 Rate of Throttled Requests on Edge Router
```logql
sum(rate({service="cosmo-router"} |= "429 Too Many Requests" [1m]))
```

#### 🧩 Structured JSON Field Unpacking & Status Filter
Parses structured JSON logs and filters requests where HTTP status $\ge 500$:
```logql
{service="cosmo-router"} | json | status_code >= 500
```

---

### 🕸️ Service Mesh & Ingress Proxy Logs (Istio Envoy)

#### 🌐 Envoy Access Logs on Edge Router Pod
```logql
{container="istio-proxy", pod=~"cosmo-router.+"}
```

#### ⏱️ Slow Ingress Requests via Envoy (> 200ms)
```logql
{container="istio-proxy"} | json | response_duration > 200
```

---

## 🔍 3. TraceQL Queries (Grafana Tempo 3.0.5 & OTel Tracing)

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
Locates traces that crossed both `cosmo-router` and `orders-service`:
```traceql
{ resource.service.name = "cosmo-router" } && { resource.service.name = "orders-service" }
```

#### 📦 Full End-to-End E-Commerce Chain (Router ➔ Orders ➔ Inventory)
Searches for traces spanning the complete multi-service synchronous checkout pipeline:
```traceql
{ resource.service.name = "cosmo-router" } && { resource.service.name = "orders-service" } && { resource.service.name = "inventory-service" }
```

#### 📨 Asynchronous Kafka Messaging Traces
Finds traces where events were published to or consumed from Kafka topics:
```traceql
{ span.messaging.system = "kafka" }
```

#### 🔍 Traces Originating from Specific GraphQL Operations
Isolates end-to-end distributed traces for specific GraphQL queries or mutations:
```traceql
# Order placement mutation journey across router and subgraphs:
{ span.graphql.operation.name = "PlaceOrder" }

# Catalog queries with federated stock:
{ span.graphql.operation.name = "GetProductsWithStock" }

# Root Cosmo Router span:
{ span.name = "router" && status = ok }

# Subgraph execution spans:
{ span.name = "subgraph" && span.graphql.subgraph.name = "orders" }
```

---

## 🛠️ Practical Quick-Reference Matrix

| Diagnostic Scenario | Recommended Tool | Query to Run |
| :--- | :---: | :--- |
| **Orders Service target down** | PromQL | `up{service="orders-service"} == 0` |
| **Cosmo Router P95 Latency** | PromQL | `histogram_quantile(0.95, sum by (le) (rate(router_http_request_duration_milliseconds_bucket{wg_subgraph_name=""}[5m])))` |
| **Supergraph Query Planning Bottleneck** | PromQL | `histogram_quantile(0.95, sum by (le) (rate(router_graphql_operation_planning_time_milliseconds_bucket[5m])))` |
| **Downstream HTTP Latency by Subgraph** | PromQL | `histogram_quantile(0.95, sum by (le, wg_subgraph_name) (rate(router_http_client_time_to_first_byte_milliseconds_bucket[5m])))` |
| **Trace a Customer Order by Operation** | TraceQL | `{ span.graphql.operation.name = "PlaceOrder" && duration > 200ms }` |
| **Circuit Breaker Tripped** | PromQL | `resilience4j_circuitbreaker_state{state="open"}` |
| **Investigate Sudden 500 Error** | LogQL | `{service=~".+"} \|~ "(?i)ERROR\|Exception"` |
| **Correlate Logs with a Trace** | LogQL | `{service=~".+"} \|= "<trace-id>"` |
| **Detect Database Pool Exhaustion**| PromQL | `hikaricp_connections_active / hikaricp_connections_max > 0.85` |
| **DDoS / Rate-Limit Blocks** | LogQL | `sum(rate({service="frontend"} \| json \| status="429" [1m]))` |
| **Identify Top Blocked Peer IPs** | LogQL | `topk(5, sum by (peer_ip) (count_over_time({service="frontend"} \| json \| status="429" [15m])))` |
| **Forecast API Down** | PromQL | `max(up{service="demand-forecast-service"}) == 0` |
| **Forecast Stale (>24h)** | PromQL | `(time() - max(demand_forecast_last_success_unixtime{service="demand-forecast-service"})) / 3600 > 24` |
| **Forecast API P95 Latency** | PromQL | `histogram_quantile(0.95, sum by (le) (rate(http_request_duration_seconds_bucket{service="demand-forecast-service"}[5m])))` |
| **Model Quality Degradation** | PromQL | `min(demand_forecast_model_rmse{service="demand-forecast-service"})` |

---

## 🧠 MLOps & Demand Forecast Alerting Guidelines (#mlops-alerts)

To prevent unmonitored model drift or silent failure of the PySpark pipeline, the platform registers automated alert rules:

```promql
# 1. Model Staleness Alert (Model older than 7 days)
demand_forecast_model_age_seconds > 604800

# 2. Input Dataset Freshness Lag (No new sales data recorded for > 3 days)
(time() - demand_forecast_last_observed_sale_unixtime) > 259200

# 3. Model Accuracy Degradation (RMSE exceeds 15 units)
demand_forecast_model_rmse > 15.0

# 4. No usable model after the API attempted a load
(demand_forecast_model_check_performed == 1) and (demand_forecast_model_available == 0)
```

The model availability rule is intentionally gated by `demand_forecast_model_check_performed`: the API checks MLflow lazily when `/api/forecast` is requested, so an idle process must not page as if a model were missing. `MLOpsForecastServiceDown` uses the stable `service="demand-forecast-service"` target label across Compose and Kubernetes, independent of each scrape job's name. These MLOps alerts are defined in the Compose Prometheus rules, the Minikube Prometheus ConfigMap, and the Helm `PrometheusRule`.

### Remediation Playbook:
1. **Model Staleness:** Check if `demand-sales-capture` is running and appending records to `/data/sales_parquet`. If auto-training is scheduled, verify `train_demand_model.py` execution logs in the MLflow UI (`http://localhost:5000`). Stop the other local runtime before switching between Compose and Minikube because they share this host port.
2. **Data Freshness Lag:** Inspect Kafka `orders-topic` partitions and consumer group `mlops-demand-history-v1` lag. If orders are placed but not DELIVERED, fulfillment status updates are required to trigger ML capture.
3. **High RMSE:** Execute data quality audit with `python mlops/data_contracts.py --input-parquet /data/sales_parquet` to check for sudden volume anomalies or negative unit quantities.
