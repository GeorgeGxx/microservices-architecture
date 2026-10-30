from dataclasses import dataclass, field
from datetime import datetime, timezone
from enum import Enum
from typing import Optional, Dict, Any
import uuid

class EventType(str, Enum):
    CART_ADD = "CART_ADD"
    CHECKOUT_START = "CHECKOUT_START"
    CHECKOUT_STEP = "CHECKOUT_STEP"
    PURCHASE_COMPLETED = "PURCHASE_COMPLETED"

class CohortType(str, Enum):
    FIRST_TIME = "first_time"
    REPEAT = "repeat"
    LOYAL_VIP = "loyal_vip"

class BasketSizeCategory(str, Enum):
    SINGLE_ITEM = "single_item"
    MEDIUM_2_3 = "2_3_items"
    BULK_4_PLUS = "bulk_4_plus"

@dataclass
class FunnelEvent:
    event_type: EventType
    category: str = "General"
    step: Optional[str] = None
    session_id: Optional[str] = None
    metadata: Dict[str, Any] = field(default_factory=dict)
    id: str = field(default_factory=lambda: str(uuid.uuid4()))
    created_at: datetime = field(default_factory=lambda: datetime.now(timezone.utc))

    def __post_init__(self):
        if not self.category or not self.category.strip():
            self.category = "General"
        if isinstance(self.event_type, str):
            self.event_type = EventType(self.event_type.upper())

@dataclass
class FunnelMetrics:
    cart_add_count: int
    checkout_start_count: int
    checkout_step_count: int
    completed_purchases: int
    cart_abandonment_rate_pct: float
    checkout_completion_rate_pct: float

    @classmethod
    def calculate(
        cls,
        cart_adds: int,
        checkout_starts: int,
        checkout_steps: int,
        purchases: int,
    ) -> "FunnelMetrics":
        if cart_adds <= 0:
            abandonment_rate = 0.0
        else:
            abandonment = max(0, cart_adds - purchases)
            abandonment_rate = round((abandonment / cart_adds) * 100.0, 2)

        completion_rate = round((purchases / checkout_starts * 100.0), 2) if checkout_starts > 0 else 0.0

        return cls(
            cart_add_count=cart_adds,
            checkout_start_count=checkout_starts,
            checkout_step_count=checkout_steps,
            completed_purchases=purchases,
            cart_abandonment_rate_pct=abandonment_rate,
            checkout_completion_rate_pct=completion_rate,
        )

@dataclass
class CustomerCohortSummary:
    first_time_orders: int = 0
    first_time_revenue: float = 0.0
    repeat_orders: int = 0
    repeat_revenue: float = 0.0
    loyal_vip_orders: int = 0
    loyal_vip_revenue: float = 0.0
