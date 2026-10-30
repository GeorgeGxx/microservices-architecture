import asyncio
import json
import logging
from aiokafka import AIOKafkaConsumer
from app.config import settings
from app.infrastructure.database import AsyncSessionLocal
from app.infrastructure.repositories import SqlAlchemyAnalyticsStateRepository, SqlAlchemyFunnelRepository
from app.domain.models import FunnelEvent, EventType
from app.infrastructure.metrics import (
    funnel_events_counter,
    cart_abandonment_gauge,
    cohort_orders_gauge,
    cohort_revenue_gauge,
    orders_gauge,
    revenue_gauge,
    active_pipeline_gauge,
    sku_sales_gauge,
)

logger = logging.getLogger("AnalyticsKafkaConsumer")

class AnalyticsKafkaConsumer:
    def __init__(self):
        self.consumer = None
        self.is_running = False
        self.consume_task = None

    async def start(self):
        brokers = settings.kafka_brokers
        topics = [settings.kafka_orders_topic, settings.kafka_payments_topic, settings.kafka_fulfillment_topic]
        logger.info(f"Connecting to Kafka brokers at {brokers} for topics: {topics}")

        # Retry loop for resilient startup
        for attempt in range(1, 15):
            try:
                self.consumer = AIOKafkaConsumer(
                    *topics,
                    bootstrap_servers=brokers,
                    group_id=settings.kafka_group_id,
                    auto_offset_reset="latest",
                    enable_auto_commit=True,
                )
                await self.consumer.start()
                self.is_running = True
                logger.info("Kafka Consumer connected successfully")
                self.consume_task = asyncio.create_task(self._consume_loop())
                return
            except Exception as e:
                if self.consumer is not None:
                    try:
                        await self.consumer.stop()
                    except Exception:
                        pass
                    self.consumer = None
                logger.warning(f"Kafka connection attempt {attempt}/15 failed: {e}. Retrying in 2s...")
                await asyncio.sleep(2)

    async def _consume_loop(self):
        try:
            async for msg in self.consumer:
                await self._process_message(msg)
        except asyncio.CancelledError:
            raise
        except Exception:
            logger.exception("Error in Kafka consume loop")

    @staticmethod
    def _is_completed_payment(topic: str, payload: dict) -> bool:
        event_type = payload.get("event_type") or payload.get("eventType") or ""
        status = payload.get("status") or payload.get("orderStatus") or ""
        is_payment = topic == settings.kafka_payments_topic or event_type == "PAYMENT_COMPLETED"
        is_failed = status in ("FAILED", "REFUNDED") or event_type in ("PAYMENT_FAILED", "PAYMENT_REFUNDED")
        return is_payment and not is_failed

    async def _record_completed_payment(
        self, order_number: str, amount: float, user_id: str, items_count: int
    ) -> None:
        async with AsyncSessionLocal() as session:
            state_repo = SqlAlchemyAnalyticsStateRepository(session)
            funnel_repo = SqlAlchemyFunnelRepository(session)

            await state_repo.record_completed_order(order_number, amount, user_id, items_count)

            purchase_event = FunnelEvent(
                event_type=EventType.PURCHASE_COMPLETED,
                category="General",
                metadata={"order_number": order_number, "amount": amount},
            )
            await funnel_repo.save_event(purchase_event)

            funnel_counts = await funnel_repo.count_events_by_type()
            sales_totals = await state_repo.get_sales_totals()
            cart_adds = funnel_counts.get("CART_ADD", 0)
            completed = sales_totals.get("completed_orders", 0)
            orders_gauge.labels("COMPLETED").set(completed)
            revenue_gauge.set(round(sales_totals.get("total_revenue_usd", 0.0), 2))
            if cart_adds > 0:
                abandonment = max(0.0, (cart_adds - completed) / cart_adds * 100.0)
                cart_abandonment_gauge.set(round(abandonment, 2))

            cohort_summary = await state_repo.get_cohort_summary()
            cohort_orders_gauge.labels("first_time").set(cohort_summary.first_time_orders)
            cohort_orders_gauge.labels("repeat").set(cohort_summary.repeat_orders)
            cohort_orders_gauge.labels("loyal_vip").set(cohort_summary.loyal_vip_orders)

            cohort_revenue_gauge.labels("first_time").set(round(cohort_summary.first_time_revenue, 2))
            cohort_revenue_gauge.labels("repeat").set(round(cohort_summary.repeat_revenue, 2))
            cohort_revenue_gauge.labels("loyal_vip").set(round(cohort_summary.loyal_vip_revenue, 2))

            logger.info(f"Processed payment event for order #{order_number}, updated analytics metrics")

    async def _process_message(self, msg):
        try:
            payload = json.loads(msg.value.decode("utf-8"))
            topic = msg.topic

            # 1. Pipeline and SKU Sales Tracking from orders-topic
            if topic == settings.kafka_orders_topic:
                status = str(payload.get("orderStatus") or payload.get("status") or "").upper()
                if status in ("PLACED", "PREPARING", "IN_TRANSIT", "OUT_FOR_DELIVERY", "DELIVERED"):
                    active_pipeline_gauge.labels(status).inc()
                if status == "CANCELLED":
                    orders_gauge.labels("CANCELLED").inc()
                for item in payload.get("items") or []:
                    sku = str(item.get("sku") or "")
                    qty = int(item.get("quantity") or 1)
                    if sku:
                        sku_sales_gauge.labels(sku).inc(qty)

            # 2. Fulfillment Tracking from fulfillment-topic
            elif topic == settings.kafka_fulfillment_topic:
                event_type = str(payload.get("eventType") or payload.get("event_type") or "").upper()
                if event_type == "SHIPMENT_DISPATCHED":
                    active_pipeline_gauge.labels("IN_TRANSIT").inc()
                elif event_type == "SHIPMENT_DELIVERED":
                    active_pipeline_gauge.labels("DELIVERED").inc()

            # 3. Completed Payment Tracking
            if self._is_completed_payment(topic, payload):
                order_number = payload.get("order_number") or payload.get("orderNumber")
                amount = float(payload.get("amount") or 0.0)
                user_id = payload.get("user_id") or payload.get("userId") or "user"
                items_count = int(payload.get("items_count") or 1)
                if order_number and amount > 0:
                    await self._record_completed_payment(order_number, amount, user_id, items_count)
        except Exception:
            logger.exception("Failed to handle Kafka message")

    async def stop(self):
        if self.consume_task and not self.consume_task.done():
            self.consume_task.cancel()
            await asyncio.gather(self.consume_task, return_exceptions=True)
        if self.consumer and self.is_running:
            self.is_running = False
            await self.consumer.stop()
            logger.info("Kafka Consumer stopped cleanly")

kafka_consumer = AnalyticsKafkaConsumer()
