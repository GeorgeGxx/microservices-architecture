import pytest
from httpx import AsyncClient, ASGITransport
from app.main import app
from app.infrastructure.database import get_db_session
from app.domain.models import FunnelEvent
from tests.test_use_cases import InMemoryFunnelRepository, InMemoryAnalyticsStateRepository

class FakeAsyncSession:
    def __init__(self):
        self.funnel_repo = InMemoryFunnelRepository()
        self.state_repo = InMemoryAnalyticsStateRepository()

@pytest.fixture
def override_db():
    fake_session = FakeAsyncSession()

    async def _override_get_db():
        yield fake_session

    app.dependency_overrides[get_db_session] = _override_get_db
    yield fake_session
    app.dependency_overrides.clear()

@pytest.mark.asyncio
async def test_health_endpoints():
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        resp = await client.get("/health")
        assert resp.status_code == 200
        data = resp.json()
        assert data["status"] == "UP"
        assert data["service"] == "analytics-service"

        actuator_resp = await client.get("/actuator/health")
        assert actuator_resp.status_code == 200

@pytest.mark.asyncio
async def test_metrics_endpoint():
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        resp = await client.get("/metrics")
        assert resp.status_code == 200
        assert "ecommerce_funnel_events_total" in resp.text
        assert "ecommerce_cart_abandonment_rate" in resp.text

@pytest.mark.asyncio
async def test_record_funnel_event_endpoint(override_db, monkeypatch):
    from app.presentation import routers

    class MockFunnelRepo:
        def __init__(self, session): pass
        async def save_event(self, event): return event
        async def count_events_by_type(self): return {"CART_ADD": 1}

    class MockStateRepo:
        def __init__(self, session): pass
        async def get_sales_totals(self): return {"completed_orders": 0}

    monkeypatch.setattr(routers, "SqlAlchemyFunnelRepository", MockFunnelRepo)
    monkeypatch.setattr(routers, "SqlAlchemyAnalyticsStateRepository", MockStateRepo)

    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        payload = {
            "event_type": "CART_ADD",
            "category": "Electronics",
            "step": "PAYMENT",
            "session_id": "test-session",
        }
        resp = await client.post("/api/v1/analytics/events", json=payload)
        assert resp.status_code == 201
        data = resp.json()
        assert data["event_type"] == "CART_ADD"
        assert data["category"] == "Electronics"

@pytest.mark.asyncio
async def test_get_funnel_and_cohorts_endpoints(override_db, monkeypatch):
    from app.presentation import routers
    from app.domain.models import CustomerCohortSummary

    class MockFunnelRepo:
        def __init__(self, session): pass
        async def count_events_by_type(self): return {"CART_ADD": 10, "CHECKOUT_START": 5}

    class MockStateRepo:
        def __init__(self, session): pass
        async def get_sales_totals(self): return {
            "completed_orders": 2,
            "total_revenue_usd": 150.0,
            "total_items_sold": 4,
            "basket_sizes": {"single_item": 1, "2_3_items": 1, "bulk_4_plus": 0},
        }
        async def get_cohort_summary(self): return CustomerCohortSummary(
            first_time_orders=1,
            first_time_revenue=50.0,
            repeat_orders=1,
            repeat_revenue=100.0,
            loyal_vip_orders=0,
            loyal_vip_revenue=0.0,
        )

    monkeypatch.setattr(routers, "SqlAlchemyFunnelRepository", MockFunnelRepo)
    monkeypatch.setattr(routers, "SqlAlchemyAnalyticsStateRepository", MockStateRepo)

    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        # Funnel
        funnel_resp = await client.get("/api/v1/analytics/funnel")
        assert funnel_resp.status_code == 200
        funnel_data = funnel_resp.json()
        assert funnel_data["cart_add_count"] == 10
        assert funnel_data["completed_purchases"] == 2
        assert funnel_data["cart_abandonment_rate_pct"] == 80.0

        # Cohorts
        cohort_resp = await client.get("/api/v1/analytics/cohorts")
        assert cohort_resp.status_code == 200
        cohort_data = cohort_resp.json()
        assert cohort_data["first_time_orders"] == 1
        assert cohort_data["repeat_revenue"] == 100.0

        # Sales overview
        sales_resp = await client.get("/api/v1/analytics/sales")
        assert sales_resp.status_code == 200
        sales_data = sales_resp.json()
        assert sales_data["completed_orders"] == 2
        assert sales_data["total_revenue_usd"] == 150.0
