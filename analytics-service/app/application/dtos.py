from pydantic import BaseModel, Field
from typing import Optional, Dict, Any, List
from datetime import datetime

class RecordFunnelEventDto(BaseModel):
    event_type: str = Field(..., example="CART_ADD", description="Type of funnel event: CART_ADD, CHECKOUT_START, CHECKOUT_STEP")
    category: Optional[str] = Field("General", example="Electronics")
    step: Optional[str] = Field(None, example="PAYMENT")
    session_id: Optional[str] = Field(None, example="sess-999")
    metadata: Optional[Dict[str, Any]] = Field(default_factory=dict)

class FunnelEventResponseDto(BaseModel):
    id: str
    event_type: str
    category: str
    step: Optional[str] = None
    session_id: Optional[str] = None
    created_at: datetime

class FunnelAnalysisResponseDto(BaseModel):
    cart_add_count: int
    checkout_start_count: int
    checkout_step_count: int
    completed_purchases: int
    cart_abandonment_rate_pct: float
    checkout_completion_rate_pct: float

class CustomerCohortResponseDto(BaseModel):
    first_time_orders: int
    first_time_revenue: float
    repeat_orders: int
    repeat_revenue: float
    loyal_vip_orders: int
    loyal_vip_revenue: float

class SalesOverviewResponseDto(BaseModel):
    completed_orders: int
    total_revenue_usd: float
    total_items_sold: int
    basket_sizes: Dict[str, int]
