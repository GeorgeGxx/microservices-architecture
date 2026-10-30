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
    # Defensive check: if purchases > cart_adds, abandonment is 0.0%
    metrics = FunnelMetrics.calculate(
        cart_adds=10,
        checkout_starts=10,
        checkout_steps=10,
        purchases=15,
    )
    assert metrics.cart_abandonment_rate_pct == 0.0
