import logging
from contextlib import asynccontextmanager
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import RedirectResponse
from app.config import settings
from app.infrastructure.database import engine, Base, AsyncSessionLocal
from app.infrastructure.repositories import SqlAlchemyAnalyticsStateRepository, SqlAlchemyFunnelRepository
from app.infrastructure.metrics import (
    orders_gauge,
    revenue_gauge,
    cohort_orders_gauge,
    cohort_revenue_gauge,
    cart_abandonment_gauge,
)
from app.infrastructure.kafka_consumer import kafka_consumer
from app.presentation.routers import router

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] [%(name)s] %(message)s",
)
logger = logging.getLogger("AnalyticsApp")

@asynccontextmanager
async def lifespan(app: FastAPI):
    # 1. Startup: Auto-create tables in PostgreSQL 18
    logger.info("Initializing PostgreSQL 18 schema for analytics-service...")
    for attempt in range(1, 15):
        try:
            async with engine.begin() as conn:
                await conn.run_sync(Base.metadata.create_all)
            logger.info("Database schema synchronized successfully")
            break
        except Exception as e:
            logger.warning(f"Database connection attempt {attempt}/15 failed: {e}. Retrying in 2s...")
            import asyncio
            await asyncio.sleep(2)

    # 1.1 Startup: Hydrate live Prometheus metrics from PostgreSQL 18 state
    try:
        async with AsyncSessionLocal() as session:
            state_repo = SqlAlchemyAnalyticsStateRepository(session)
            funnel_repo = SqlAlchemyFunnelRepository(session)
            totals = await state_repo.get_sales_totals()
            cohort = await state_repo.get_cohort_summary()
            funnel_counts = await funnel_repo.count_events_by_type()

            completed = totals.get("completed_orders", 0)
            orders_gauge.labels("COMPLETED").set(completed)
            revenue_gauge.set(round(totals.get("total_revenue_usd", 0.0), 2))

            cart_adds = funnel_counts.get("CART_ADD", 0)
            if cart_adds > 0:
                abandonment = max(0.0, (cart_adds - completed) / cart_adds * 100.0)
                cart_abandonment_gauge.set(round(abandonment, 2))

            cohort_orders_gauge.labels("first_time").set(cohort.first_time_orders)
            cohort_orders_gauge.labels("repeat").set(cohort.repeat_orders)
            cohort_orders_gauge.labels("loyal_vip").set(cohort.loyal_vip_orders)

            cohort_revenue_gauge.labels("first_time").set(round(cohort.first_time_revenue, 2))
            cohort_revenue_gauge.labels("repeat").set(round(cohort.repeat_revenue, 2))
            cohort_revenue_gauge.labels("loyal_vip").set(round(cohort.loyal_vip_revenue, 2))
            logger.info(f"Hydrated Prometheus metrics: {completed} orders, ${totals.get('total_revenue_usd', 0.0):.2f} revenue")
    except Exception as e:
        logger.warning(f"Metrics hydration notice: {e}")

    # 2. Start Kafka consumer
    await kafka_consumer.start()

    yield

    # 3. Shutdown: Disconnect Kafka and database engine
    logger.info("Shutting down analytics-service...")
    await kafka_consumer.stop()
    await engine.dispose()
    logger.info("Cleanup completed")

app = FastAPI(
    title="Analytics Service API",
    description="Real-time e-commerce analytics, shopping cart abandonment rate and customer loyalty cohort tracking",
    version="1.0.0",
    docs_url="/docs",
    redoc_url="/redoc",
    openapi_url="/openapi.json",
    lifespan=lifespan,
    contact={
        "name": "Novashop Platform Engineering",
        "email": "dev@novashop.local",
    },
    license_info={
        "name": "MIT License",
        "url": "https://opensource.org/licenses/MIT",
    },
    openapi_tags=[
        {"name": "analytics", "description": "Business analytics, sales overview and customer loyalty cohorts"},
        {"name": "funnel", "description": "E-commerce user interaction funnel tracking"},
        {"name": "health", "description": "Service health probes and Prometheus metrics"},
    ],
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

@app.get("/swagger", include_in_schema=False)
@app.get("/swagger-ui", include_in_schema=False)
@app.get("/swagger-ui.html", include_in_schema=False)
async def swagger_ui_redirect():
    """Redirect alternative swagger URLs to the OpenAPI Swagger documentation."""
    return RedirectResponse(url="/docs")

app.include_router(router)

if __name__ == "__main__":
    import uvicorn
    uvicorn.run("app.main:app", host=settings.server_host, port=settings.server_port, reload=True)
