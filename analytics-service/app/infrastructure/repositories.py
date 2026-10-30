import uuid
from typing import Dict, Any
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, func
from app.domain.models import FunnelEvent, CustomerCohortSummary
from app.domain.repositories import FunnelRepository, AnalyticsStateRepository
from app.infrastructure.orm_models import FunnelEventOrm, OrderSaleOrm

class SqlAlchemyFunnelRepository(FunnelRepository):
    def __init__(self, session: AsyncSession):
        self.session = session

    async def save_event(self, event: FunnelEvent) -> FunnelEvent:
        orm = FunnelEventOrm(
            id=event.id,
            event_type=event.event_type.value,
            category=event.category,
            step=event.step,
            session_id=event.session_id,
            event_metadata=event.metadata,
            created_at=event.created_at,
        )
        self.session.add(orm)
        await self.session.commit()
        return event

    async def count_events_by_type(self) -> Dict[str, int]:
        stmt = select(FunnelEventOrm.event_type, func.count(FunnelEventOrm.id)).group_by(FunnelEventOrm.event_type)
        result = await self.session.execute(stmt)
        return {row[0]: row[1] for row in result.all()}

class SqlAlchemyAnalyticsStateRepository(AnalyticsStateRepository):
    def __init__(self, session: AsyncSession):
        self.session = session

    async def record_completed_order(self, order_number: str, amount: float, user_id: str, items_count: int) -> None:
        # Check if already recorded (idempotent)
        existing = await self.session.execute(select(OrderSaleOrm).where(OrderSaleOrm.order_number == order_number))
        if existing.scalar_one_or_none():
            return

        sale = OrderSaleOrm(
            id=str(uuid.uuid4()),
            order_number=order_number,
            amount=amount,
            user_id=user_id or "guest",
            items_count=items_count or 1,
        )
        self.session.add(sale)
        await self.session.commit()

    async def get_cohort_summary(self) -> CustomerCohortSummary:
        # Group sales by user
        stmt = select(
            OrderSaleOrm.user_id,
            func.count(OrderSaleOrm.id).label("order_count"),
            func.sum(OrderSaleOrm.amount).label("total_spend"),
        ).where(OrderSaleOrm.user_id != "guest").group_by(OrderSaleOrm.user_id)

        result = await self.session.execute(stmt)
        rows = result.all()

        first_time_orders, first_time_rev = 0, 0.0
        repeat_orders, repeat_rev = 0, 0.0
        vip_orders, vip_rev = 0, 0.0

        for row in rows:
            count = row.order_count
            spend = float(row.total_spend or 0.0)

            if count <= 1:
                first_time_orders += count
                first_time_rev += spend
            elif count <= 4:
                repeat_orders += count
                repeat_rev += spend
            else:
                vip_orders += count
                vip_rev += spend

        return CustomerCohortSummary(
            first_time_orders=first_time_orders,
            first_time_revenue=first_time_rev,
            repeat_orders=repeat_orders,
            repeat_revenue=repeat_rev,
            loyal_vip_orders=vip_orders,
            loyal_vip_revenue=vip_rev,
        )

    async def get_sales_totals(self) -> Dict[str, Any]:
        stmt = select(
            func.count(OrderSaleOrm.id),
            func.coalesce(func.sum(OrderSaleOrm.amount), 0.0),
            func.coalesce(func.sum(OrderSaleOrm.items_count), 0),
        )
        result = await self.session.execute(stmt)
        total_count, total_rev, total_items = result.one()

        # Basket sizes
        sales_stmt = select(OrderSaleOrm.items_count)
        items_result = await self.session.execute(sales_stmt)
        basket_counts = {"single_item": 0, "2_3_items": 0, "bulk_4_plus": 0}
        for item in items_result.scalars():
            if item <= 1:
                basket_counts["single_item"] += 1
            elif item <= 3:
                basket_counts["2_3_items"] += 1
            else:
                basket_counts["bulk_4_plus"] += 1

        return {
            "completed_orders": int(total_count or 0),
            "total_revenue_usd": float(total_rev or 0.0),
            "total_items_sold": int(total_items or 0),
            "basket_sizes": basket_counts,
        }
