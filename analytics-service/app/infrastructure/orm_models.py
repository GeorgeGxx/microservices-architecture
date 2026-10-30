from sqlalchemy import Column, String, DateTime, Float, Integer, JSON
from datetime import datetime, timezone
from app.infrastructure.database import Base

class FunnelEventOrm(Base):
    __tablename__ = "funnel_events"

    id = Column(String(36), primary_key=True)
    event_type = Column(String(50), nullable=False, index=True)
    category = Column(String(50), nullable=False, default="General")
    step = Column(String(50), nullable=True)
    session_id = Column(String(100), nullable=True, index=True)
    event_metadata = Column("metadata", JSON, nullable=True)
    created_at = Column(DateTime(timezone=True), default=lambda: datetime.now(timezone.utc), nullable=False)

class OrderSaleOrm(Base):
    __tablename__ = "order_sales"

    id = Column(String(36), primary_key=True)
    order_number = Column(String(64), unique=True, nullable=False, index=True)
    amount = Column(Float, nullable=False)
    user_id = Column(String(100), nullable=False, index=True)
    items_count = Column(Integer, default=1, nullable=False)
    created_at = Column(DateTime(timezone=True), default=lambda: datetime.now(timezone.utc), nullable=False)
