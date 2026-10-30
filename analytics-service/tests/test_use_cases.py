import pytest
from typing import Dict, Any
from app.domain.models import FunnelEvent, CustomerCohortSummary
from app.domain.repositories import FunnelRepository, AnalyticsStateRepository
from app.application.dtos import RecordFunnelEventDto
from app.application.use_cases import (
    RecordFunnelEventUseCase,
    GetFunnelAnalysisUseCase,
    GetCustomerCohortsUseCase,
    GetSalesOverviewUseCase,
)

class InMemoryFunnelRepository(FunnelRepository):
    def __init__(self):
        self.events = []

    async def save_event(self, event: FunnelEvent) -> FunnelEvent:
        self.events.append(event)
        return event

    async def count_events_by_type(self) -> Dict[str, int]:
        counts = {}
        for e in self.events:
            val = e.event_type.value if hasattr(e.event_type, "value") else str(e.event_type)
            counts[val] = counts.get(val, 0) + 1
        return counts

class InMemoryAnalyticsStateRepository(AnalyticsStateRepository):
    def __init__(self):
        self.sales = []

    async def record_completed_order(self, order_number: str, amount: float, user_id: str, items_count: int) -> None:
        self.sales.append({
            "order_number": order_number,
            "amount": amount,
            "user_id": user_id,
            "items_count": items_count,
        })

    async def get_cohort_summary(self) -> CustomerCohortSummary:
        return CustomerCohortSummary(
            first_time_orders=5,
            first_time_revenue=250.0,
            repeat_orders=8,
            repeat_revenue=720.0,
            loyal_vip_orders=15,
            loyal_vip_revenue=2100.0,
        )

    async def get_sales_totals(self) -> Dict[str, Any]:
        return {
            "completed_orders": len(self.sales),
            "total_revenue_usd": sum(s["amount"] for s in self.sales),
            "total_items_sold": sum(s["items_count"] for s in self.sales),
            "basket_sizes": {"single_item": 2, "2_3_items": 3, "bulk_4_plus": 1},
        }

@pytest.mark.asyncio
async def test_record_funnel_event_use_case():
    repo = InMemoryFunnelRepository()
    use_case = RecordFunnelEventUseCase(repo)

    dto = RecordFunnelEventDto(
        event_type="CART_ADD",
        category="Computers",
        step="SHIPPING",
        session_id="sess-001",
    )
    result = await use_case.execute(dto)

    assert result.event_type == "CART_ADD"
    assert result.category == "Computers"
    assert len(repo.events) == 1

@pytest.mark.asyncio
async def test_get_funnel_analysis_use_case():
    funnel_repo = InMemoryFunnelRepository()
    state_repo = InMemoryAnalyticsStateRepository()

    # Ingest 50 cart adds, 20 checkout starts
    for _ in range(50):
        await funnel_repo.save_event(FunnelEvent(event_type="CART_ADD"))
    for _ in range(20):
        await funnel_repo.save_event(FunnelEvent(event_type="CHECKOUT_START"))

    # Ingest 10 completed orders
    for i in range(10):
        await state_repo.record_completed_order(f"ORD-{i}", 100.0, f"user-{i}", 2)

    use_case = GetFunnelAnalysisUseCase(funnel_repo, state_repo)
    analysis = await use_case.execute()

    assert analysis.cart_add_count == 50
    assert analysis.checkout_start_count == 20
    assert analysis.completed_purchases == 10
    # (50 - 10) / 50 = 80.0%
    assert analysis.cart_abandonment_rate_pct == 80.0

@pytest.mark.asyncio
async def test_get_customer_cohorts_and_sales_overview():
    state_repo = InMemoryAnalyticsStateRepository()
    await state_repo.record_completed_order("ORD-01", 50.0, "user-1", 1)

    cohorts_use_case = GetCustomerCohortsUseCase(state_repo)
    cohorts = await cohorts_use_case.execute()
    assert cohorts.first_time_orders == 5
    assert cohorts.loyal_vip_revenue == 2100.0

    sales_use_case = GetSalesOverviewUseCase(state_repo)
    sales = await sales_use_case.execute()
    assert sales.completed_orders == 1
    assert sales.total_revenue_usd == 50.0
