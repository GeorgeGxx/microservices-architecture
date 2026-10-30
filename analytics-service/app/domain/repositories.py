from abc import ABC, abstractmethod
from typing import List, Dict, Optional, Any
from app.domain.models import FunnelEvent, FunnelMetrics, CustomerCohortSummary

class FunnelRepository(ABC):
    @abstractmethod
    async def save_event(self, event: FunnelEvent) -> FunnelEvent:
        pass

    @abstractmethod
    async def count_events_by_type(self) -> Dict[str, int]:
        pass

class AnalyticsStateRepository(ABC):
    @abstractmethod
    async def record_completed_order(self, order_number: str, amount: float, user_id: str, items_count: int) -> None:
        pass

    @abstractmethod
    async def get_cohort_summary(self) -> CustomerCohortSummary:
        pass

    @abstractmethod
    async def get_sales_totals(self) -> Dict[str, Any]:
        pass
