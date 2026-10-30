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

def get_prometheus_metrics() -> bytes:
    return generate_latest()
