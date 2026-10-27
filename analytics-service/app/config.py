import os
from pydantic import BaseModel

class Settings(BaseModel):
    server_port: int = int(os.getenv("PORT", "8087"))
    db_host: str = os.getenv("DB_HOST", "localhost")
    db_port: int = int(os.getenv("DB_PORT", "5438"))
    db_user: str = os.getenv("DB_USER", "postgres")
    db_password: str = os.getenv("DB_PASSWORD", "admin")
    db_name: str = os.getenv("DB_NAME", "ms_analytics")
    kafka_brokers: str = os.getenv("KAFKA_BOOTSTRAP_SERVERS", "localhost:9092")
    kafka_orders_topic: str = os.getenv("KAFKA_ORDERS_TOPIC", "orders-topic")
    kafka_payments_topic: str = os.getenv("KAFKA_PAYMENTS_TOPIC", "payments-topic")
    kafka_fulfillment_topic: str = os.getenv("KAFKA_FULFILLMENT_TOPIC", "fulfillment-topic")
    kafka_group_id: str = os.getenv("KAFKA_GROUP_ID", "analytics-service-group")
    environment: str = os.getenv("ENV", "development")

    @property
    def database_url(self) -> str:
        return f"postgresql+asyncpg://{self.db_user}:{self.db_password}@{self.db_host}:{self.db_port}/{self.db_name}"

settings = Settings()
