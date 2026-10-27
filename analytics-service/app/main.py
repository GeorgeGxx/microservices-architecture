import logging
from contextlib import asynccontextmanager
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from app.config import settings
from app.infrastructure.database import engine, Base
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
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(router)

if __name__ == "__main__":
    import uvicorn
    uvicorn.run("app.main:app", host="0.0.0.0", port=settings.server_port, reload=True)
