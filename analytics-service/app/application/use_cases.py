from app.domain.models import FunnelEvent, EventType, FunnelMetrics
from app.domain.repositories import FunnelRepository, AnalyticsStateRepository
from app.application.dtos import (
    RecordFunnelEventDto,
    FunnelEventResponseDto,
    FunnelAnalysisResponseDto,
    CustomerCohortResponseDto,
    SalesOverviewResponseDto,
)

class RecordFunnelEventUseCase:
    def __init__(self, repository: FunnelRepository):
        self.repository = repository

    async def execute(self, dto: RecordFunnelEventDto) -> FunnelEventResponseDto:
        event = FunnelEvent(
            event_type=EventType(dto.event_type.upper()),
            category=dto.category or "General",
            step=dto.step.upper() if dto.step else None,
            session_id=dto.session_id,
            metadata=dto.metadata or {},
        )
        saved = await self.repository.save_event(event)
        return FunnelEventResponseDto(
            id=saved.id,
            event_type=saved.event_type.value,
            category=saved.category,
            step=saved.step,
            session_id=saved.session_id,
            created_at=saved.created_at,
        )

class GetFunnelAnalysisUseCase:
    def __init__(self, funnel_repo: FunnelRepository, state_repo: AnalyticsStateRepository):
        self.funnel_repo = funnel_repo
        self.state_repo = state_repo

    async def execute(self) -> FunnelAnalysisResponseDto:
        counts = await self.funnel_repo.count_events_by_type()
        sales = await self.state_repo.get_sales_totals()

        cart_adds = counts.get(EventType.CART_ADD.value, 0)
        checkout_starts = counts.get(EventType.CHECKOUT_START.value, 0)
        checkout_steps = counts.get(EventType.CHECKOUT_STEP.value, 0)
        completed = sales.get("completed_orders", 0)

        metrics = FunnelMetrics.calculate(cart_adds, checkout_starts, checkout_steps, completed)

        return FunnelAnalysisResponseDto(
            cart_add_count=metrics.cart_add_count,
            checkout_start_count=metrics.checkout_start_count,
            checkout_step_count=metrics.checkout_step_count,
            completed_purchases=metrics.completed_purchases,
            cart_abandonment_rate_pct=metrics.cart_abandonment_rate_pct,
            checkout_completion_rate_pct=metrics.checkout_completion_rate_pct,
        )

class GetCustomerCohortsUseCase:
    def __init__(self, state_repo: AnalyticsStateRepository):
        self.state_repo = state_repo

    async def execute(self) -> CustomerCohortResponseDto:
        summary = await self.state_repo.get_cohort_summary()
        return CustomerCohortResponseDto(
            first_time_orders=summary.first_time_orders,
            first_time_revenue=round(summary.first_time_revenue, 2),
            repeat_orders=summary.repeat_orders,
            repeat_revenue=round(summary.repeat_revenue, 2),
            loyal_vip_orders=summary.loyal_vip_orders,
            loyal_vip_revenue=round(summary.loyal_vip_revenue, 2),
        )

class GetSalesOverviewUseCase:
    def __init__(self, state_repo: AnalyticsStateRepository):
        self.state_repo = state_repo

    async def execute(self) -> SalesOverviewResponseDto:
        totals = await self.state_repo.get_sales_totals()
        return SalesOverviewResponseDto(
            completed_orders=totals.get("completed_orders", 0),
            total_revenue_usd=round(totals.get("total_revenue_usd", 0.0), 2),
            total_items_sold=totals.get("total_items_sold", 0),
            basket_sizes=totals.get("basket_sizes", {
                "single_item": 0,
                "2_3_items": 0,
                "bulk_4_plus": 0,
            }),
        )
