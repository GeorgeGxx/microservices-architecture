from prometheus_client import Counter, Gauge, generate_latest, CONTENT_TYPE_LATEST

funnel_events_counter = Counter(
    "ecommerce_funnel_events_total",
    "Funnel events ingested from ecommerce storefront",
    ["event_type", "category", "step"],
)

cart_abandonment_gauge = Gauge(
    "ecommerce_cart_abandonment_rate",
    "Real-time cart abandonment rate percentage",
)

cohort_orders_gauge = Gauge(
    "ecommerce_orders_by_cohort",
    "Completed orders partitioned by customer loyalty cohort",
    ["cohort"],
)

cohort_revenue_gauge = Gauge(
    "ecommerce_revenue_by_cohort_usd",
    "Delivered revenue partitioned by customer loyalty cohort in USD",
    ["cohort"],
)

orders_gauge = Gauge(
    "ecommerce_orders",
    "Total orders partitioned by lifecycle status",
    ["status"],
)

revenue_gauge = Gauge(
    "ecommerce_revenue_usd",
    "Total net sales revenue from completed orders in USD",
)

active_pipeline_gauge = Gauge(
    "ecommerce_orders_active_in_pipeline",
    "Active orders across 5-stage logistics pipeline",
    ["status"],
)

sku_sales_gauge = Gauge(
    "ecommerce_sku_sales",
    "Total units sold per product SKU",
    ["sku"],
)

def initialize_metrics() -> None:
    orders_gauge.labels("COMPLETED").set(0)
    orders_gauge.labels("CANCELLED").set(0)
    revenue_gauge.set(0.0)
    cart_abandonment_gauge.set(0.0)
    for c in ["first_time", "repeat", "loyal_vip"]:
        cohort_orders_gauge.labels(c).set(0)
        cohort_revenue_gauge.labels(c).set(0.0)
    for s in ["PLACED", "PREPARING", "IN_TRANSIT", "OUT_FOR_DELIVERY", "DELIVERED"]:
        active_pipeline_gauge.labels(s).set(0)
    for sku in ["000001", "000002", "000003", "000004", "LAPTOP-PRO"]:
        sku_sales_gauge.labels(sku).set(0)

initialize_metrics()

def get_prometheus_metrics() -> bytes:
    return generate_latest()
