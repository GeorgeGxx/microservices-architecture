from fastapi import APIRouter, Depends, Response, status
from sqlalchemy.ext.asyncio import AsyncSession
from app.infrastructure.database import get_db_session
from app.infrastructure.repositories import SqlAlchemyFunnelRepository, SqlAlchemyAnalyticsStateRepository
from app.application.dtos import (
    RecordFunnelEventDto,
    FunnelEventResponseDto,
    FunnelAnalysisResponseDto,
    CustomerCohortResponseDto,
    SalesOverviewResponseDto,
)
from app.application.use_cases import (
    RecordFunnelEventUseCase,
    GetFunnelAnalysisUseCase,
    GetCustomerCohortsUseCase,
    GetSalesOverviewUseCase,
)
from app.infrastructure.metrics import (
    get_prometheus_metrics,
    funnel_events_counter,
    cart_abandonment_gauge,
    cohort_orders_gauge,
    cohort_revenue_gauge,
)

router = APIRouter()

@router.post(
    "/api/v1/analytics/events",
    response_model=FunnelEventResponseDto,
    status_code=status.HTTP_201_CREATED,
    tags=["funnel"],
    summary="Record e-commerce user funnel interaction event",
)
async def record_funnel_event(
    dto: RecordFunnelEventDto,
    session: AsyncSession = Depends(get_db_session),
):
    repo = SqlAlchemyFunnelRepository(session)
    state_repo = SqlAlchemyAnalyticsStateRepository(session)
    use_case = RecordFunnelEventUseCase(repo)

    result = await use_case.execute(dto)

    # Increment Prometheus metric
    funnel_events_counter.labels(
        event_type=result.event_type.lower(),
        category=result.category,
        step=result.step or "",
    ).inc()

    # Recalculate Abandonment Rate gauge
    analysis_use_case = GetFunnelAnalysisUseCase(repo, state_repo)
    analysis = await analysis_use_case.execute()
    cart_abandonment_gauge.set(analysis.cart_abandonment_rate_pct)

    return result

@router.get(
    "/api/v1/analytics/funnel",
    response_model=FunnelAnalysisResponseDto,
    tags=["analytics"],
    summary="Get real-time shopping cart abandonment and funnel conversion rates",
)
async def get_funnel_analysis(session: AsyncSession = Depends(get_db_session)):
    funnel_repo = SqlAlchemyFunnelRepository(session)
    state_repo = SqlAlchemyAnalyticsStateRepository(session)
    use_case = GetFunnelAnalysisUseCase(funnel_repo, state_repo)
    analysis = await use_case.execute()
    cart_abandonment_gauge.set(analysis.cart_abandonment_rate_pct)
    return analysis

@router.get(
    "/api/v1/analytics/cohorts",
    response_model=CustomerCohortResponseDto,
    tags=["analytics"],
    summary="Get customer loyalty cohorts (first-time, repeat, loyal VIP)",
)
async def get_cohorts(session: AsyncSession = Depends(get_db_session)):
    state_repo = SqlAlchemyAnalyticsStateRepository(session)
    use_case = GetCustomerCohortsUseCase(state_repo)
    cohorts = await use_case.execute()

    # Sync Prometheus gauges
    cohort_orders_gauge.labels("first_time").set(cohorts.first_time_orders)
    cohort_orders_gauge.labels("repeat").set(cohorts.repeat_orders)
    cohort_orders_gauge.labels("loyal_vip").set(cohorts.loyal_vip_orders)

    cohort_revenue_gauge.labels("first_time").set(cohorts.first_time_revenue)
    cohort_revenue_gauge.labels("repeat").set(cohorts.repeat_revenue)
    cohort_revenue_gauge.labels("loyal_vip").set(cohorts.loyal_vip_revenue)

    return cohorts

@router.get(
    "/api/v1/analytics/sales",
    response_model=SalesOverviewResponseDto,
    tags=["analytics"],
    summary="Get overall completed order volume, items sold and basket sizes",
)
async def get_sales_overview(session: AsyncSession = Depends(get_db_session)):
    state_repo = SqlAlchemyAnalyticsStateRepository(session)
    use_case = GetSalesOverviewUseCase(state_repo)
    return await use_case.execute()

@router.get("/health", tags=["system"], summary="Service operational health check")
async def health_check():
    return {
        "status": "UP",
        "service": "analytics-service",
        "framework": "fastapi-0.115",
        "orm": "sqlalchemy-2.0-async",
        "runtime": "python-3.12",
    }

@router.get("/actuator/health", tags=["system"], summary="Spring Boot compatible health check")
async def actuator_health():
    return await health_check()

@router.get("/metrics", tags=["system"], summary="Prometheus telemetry scrape endpoint")
async def metrics_endpoint():
    return Response(content=get_prometheus_metrics(), media_type="text/plain; version=0.0.4")
