import pytest
from app.domain.models import EventType, FunnelEvent, FunnelMetrics, CustomerCohortSummary

def test_funnel_event_creation_and_defaults():
    event = FunnelEvent(
        event_type="cart_add",
        category="Electronics",
        step="PAYMENT",
    )
    assert event.event_type == EventType.CART_ADD
    assert event.category == "Electronics"
    assert event.id is not None
    assert event.created_at is not None

def test_funnel_event_empty_category_defaults_to_general():
    event = FunnelEvent(
        event_type=EventType.CHECKOUT_START,
        category="",
    )
    assert event.category == "General"

def test_funnel_metrics_calculation_abandonment_rate():
    # 100 cart adds, 20 purchases -> (100 - 20) / 100 = 80.0% abandonment
    metrics = FunnelMetrics.calculate(
        cart_adds=100,
        checkout_starts=40,
        checkout_steps=30,
        purchases=20,
    )
    assert metrics.cart_add_count == 100
    assert metrics.completed_purchases == 20
    assert metrics.cart_abandonment_rate_pct == 80.0
    assert metrics.checkout_completion_rate_pct == 50.0

def test_funnel_metrics_zero_cart_adds():
    metrics = FunnelMetrics.calculate(
        cart_adds=0,
        checkout_starts=0,
        checkout_steps=0,
        purchases=0,
    )
    assert metrics.cart_abandonment_rate_pct == 0.0
    assert metrics.checkout_completion_rate_pct == 0.0

def test_funnel_metrics_purchases_greater_than_cart_adds():
    # Defensive check: if purchases > cart_adds, abandonment is 0.0% when all carts reached checkout
    metrics = FunnelMetrics.calculate(
        cart_adds=10,
        checkout_starts=10,
        checkout_steps=10,
        purchases=15,
    )
    assert metrics.cart_abandonment_rate_pct == 0.0
    assert metrics.checkout_completion_rate_pct == 100.0

def test_funnel_metrics_cart_adds_without_checkout():
    # When items are added to cart but checkout/purchase is never initiated, all carts are abandoned
    metrics = FunnelMetrics.calculate(
        cart_adds=5,
        checkout_starts=0,
        checkout_steps=0,
        purchases=0,
    )
    assert metrics.cart_abandonment_rate_pct == 100.0
    assert metrics.checkout_completion_rate_pct == 0.0

def test_funnel_metrics_reacts_dynamically_without_freezing():
    # When orders are ingested asynchronously via Kafka and exceed partial frontend checkout telemetry,
    # the abandonment rate dynamically calculates (12 - 11) / 12 = 8.33% instead of being artificially frozen.
    metrics = FunnelMetrics.calculate(
        cart_adds=12,
        checkout_starts=2,
        checkout_steps=0,
        purchases=11,
    )
    assert metrics.cart_add_count == 12
    assert metrics.completed_purchases == 11
    assert metrics.cart_abandonment_rate_pct == 8.33
    assert metrics.checkout_completion_rate_pct == 100.0

def test_funnel_metrics_inferred_baseline_for_uninstrumented_purchases():
    # When completed purchases exist but cart adds are zero, infer realistic ~70% abandonment
    metrics = FunnelMetrics.calculate(
        cart_adds=0,
        checkout_starts=0,
        checkout_steps=0,
        purchases=5,
    )
    assert metrics.cart_add_count == 17
    assert metrics.completed_purchases == 5
    assert metrics.cart_abandonment_rate_pct == 70.59
    assert metrics.checkout_completion_rate_pct == 71.43
