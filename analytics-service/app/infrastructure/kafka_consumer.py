import asyncio
from collections import OrderedDict
import json
import logging
from typing import Optional
from aiokafka import AIOKafkaConsumer
from app.config import settings
from app.infrastructure.database import AsyncSessionLocal
from app.infrastructure.orm_models import ProcessedAnalyticsEventOrm
from app.infrastructure.repositories import SqlAlchemyAnalyticsStateRepository, SqlAlchemyFunnelRepository
from app.domain.models import FunnelEvent, EventType, FunnelMetrics
from app.domain.event_contracts import (
    OrderEventContract,
    PaymentEventContract,
    FulfillmentEventContract,
    OrderItemContract,
    unpack_cloud_event,
)
from app.infrastructure.metrics import (
    cart_abandonment_gauge,
    cohort_orders_gauge,
    cohort_revenue_gauge,
    orders_gauge,
    revenue_gauge,
    active_pipeline_gauge,
    sku_sales_gauge,
)

logger = logging.getLogger("AnalyticsKafkaConsumer")

PIPELINE_STATUSES = {"PLACED", "SHIPPED", "DELIVERED"}
FULFILLMENT_STATUS_MAP = {
    "SHIPMENT_DISPATCHED": "SHIPPED",
    "IN_TRANSIT": "SHIPPED",
    "SHIPMENT_DELIVERED": "DELIVERED",
    "SHIPMENT_CANCELLED": "CANCELLED",
}


class AnalyticsKafkaConsumer:
    MAX_LRU_DEDUP_KEYS = 10000

    def __init__(self):
        self.consumer = None
        self.is_running = False
        self.consume_task = None
        self._order_stages: dict[str, str] = {}
        self._processed_event_ids: OrderedDict[str, None] = OrderedDict()

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
                    auto_offset_reset=settings.kafka_auto_offset_reset,
                    enable_auto_commit=False,
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
                committed = False
                for attempt in range(1, 4):
                    should_commit = await self._process_message(msg)
                    if should_commit:
                        if self.consumer:
                            await self.consumer.commit()
                        committed = True
                        break
                    await asyncio.sleep(min(2 ** attempt, 5))
                if not committed:
                    logger.error(
                        "Failed to process Kafka message on topic %s after 3 attempts; offset not committed",
                        getattr(msg, "topic", "unknown"),
                    )
        except asyncio.CancelledError:
            raise
        except Exception:
            logger.exception("Error in Kafka consume loop")

    @staticmethod
    def _is_completed_payment(topic: str, payment: PaymentEventContract) -> bool:
        event_type = (payment.event_type or "").upper()
        status = (payment.status or "").upper()
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
            checkout_starts = funnel_counts.get("CHECKOUT_START", 0)
            checkout_steps = funnel_counts.get("CHECKOUT_STEP", 0)
            completed = sales_totals.get("completed_orders", 0)
            orders_gauge.labels("COMPLETED").set(completed)
            revenue_gauge.set(round(sales_totals.get("total_revenue_usd", 0.0), 2))
            metrics = FunnelMetrics.calculate(cart_adds, checkout_starts, checkout_steps, completed)
            cart_abandonment_gauge.set(metrics.cart_abandonment_rate_pct)

            cohort_summary = await state_repo.get_cohort_summary()
            cohort_orders_gauge.labels("first_time").set(cohort_summary.first_time_orders)
            cohort_orders_gauge.labels("repeat").set(cohort_summary.repeat_orders)
            cohort_orders_gauge.labels("loyal_vip").set(cohort_summary.loyal_vip_orders)

            cohort_revenue_gauge.labels("first_time").set(round(cohort_summary.first_time_revenue, 2))
            cohort_revenue_gauge.labels("repeat").set(round(cohort_summary.repeat_revenue, 2))
            cohort_revenue_gauge.labels("loyal_vip").set(round(cohort_summary.loyal_vip_revenue, 2))

            logger.info(f"Processed payment event for order #{order_number}, updated analytics metrics")

    @staticmethod
    async def _track_sku_sales(items: Optional[list[OrderItemContract]]) -> None:
        if not items:
            return
        async with AsyncSessionLocal() as session:
            state_repo = SqlAlchemyAnalyticsStateRepository(session)
            for item in items:
                sku = item.sku
                if sku:
                    qty = int(item.quantity or 1)
                    sku_sales_gauge.labels(str(sku)).inc(qty)
                    await state_repo.record_sku_sales(str(sku), qty)

    def _update_pipeline_stage(self, order_number: Optional[str], new_status: str) -> None:
        if not order_number:
            if new_status in PIPELINE_STATUSES:
                active_pipeline_gauge.labels(new_status).inc()
            elif new_status == "CANCELLED":
                orders_gauge.labels("CANCELLED").inc()
            return

        old_status = self._order_stages.get(order_number)
        if old_status == new_status:
            return

        if old_status in PIPELINE_STATUSES:
            try:
                active_pipeline_gauge.labels(old_status).dec()
            except Exception:
                pass

        if new_status in PIPELINE_STATUSES:
            active_pipeline_gauge.labels(new_status).inc()
            self._order_stages[order_number] = new_status
        elif new_status == "CANCELLED":
            orders_gauge.labels("CANCELLED").inc()
            self._order_stages[order_number] = "CANCELLED"
        else:
            self._order_stages.pop(order_number, None)

    async def _handle_orders_event(self, order_data: dict) -> None:
        order = OrderEventContract.model_validate(order_data)
        status = (order.order_status or "").upper()
        if status == "IN_TRANSIT":
            status = "SHIPPED"
        if status:
            self._update_pipeline_stage(order.order_number, status)

        try:
            await self._track_sku_sales(order.items)
        except Exception:
            pass

    def _handle_fulfillment_event(self, fulfillment_data: dict) -> None:
        fulfillment = FulfillmentEventContract.model_validate(fulfillment_data)
        event_type = (fulfillment.event_type or "").upper()
        mapped_status = FULFILLMENT_STATUS_MAP.get(event_type)
        if mapped_status:
            self._update_pipeline_stage(fulfillment.order_number, mapped_status)

    async def _handle_payment_event(self, topic: str, payment_data: dict) -> None:
        payment = PaymentEventContract.model_validate(payment_data)
        if not self._is_completed_payment(topic, payment):
            return

        order_number = payment.order_number
        amount = float(payment.amount or 0.0)
        user_id = payment.user_id or "user"
        items_count = int(payment.items_count or 1)
        if order_number and amount > 0:
            await self._record_completed_payment(order_number, amount, user_id, items_count)

    def _remember_dedup_key(self, dedup_key: str) -> None:
        if not dedup_key:
            return
        self._processed_event_ids[dedup_key] = None
        self._processed_event_ids.move_to_end(dedup_key)
        while len(self._processed_event_ids) > self.MAX_LRU_DEDUP_KEYS:
            self._processed_event_ids.popitem(last=False)

    async def _is_durably_processed(self, dedup_key: str) -> bool:
        if not dedup_key:
            return False
        if dedup_key in self._processed_event_ids:
            self._processed_event_ids.move_to_end(dedup_key)
            return True
        try:
            async with AsyncSessionLocal() as session:
                get_fn = getattr(session, "get", None)
                if callable(get_fn):
                    existing = await get_fn(ProcessedAnalyticsEventOrm, dedup_key)
                    if isinstance(existing, ProcessedAnalyticsEventOrm):
                        self._remember_dedup_key(dedup_key)
                        return True
        except Exception:
            pass
        return False

    async def _mark_durably_processed(self, dedup_key: str, topic: str) -> None:
        if not dedup_key:
            return
        self._remember_dedup_key(dedup_key)
        try:
            async with AsyncSessionLocal() as session:
                add_fn = getattr(session, "add", None)
                commit_fn = getattr(session, "commit", None)
                if callable(add_fn) and callable(commit_fn):
                    add_fn(ProcessedAnalyticsEventOrm(event_key=dedup_key, topic=topic or "unknown"))
                    await commit_fn()
        except Exception:
            pass

    async def _process_message(self, msg) -> bool:
        try:
            raw_payload = json.loads(msg.value.decode("utf-8"))
        except Exception:
            logger.warning("Dropping malformed JSON payload on topic %s", getattr(msg, "topic", "unknown"))
            return True

        try:
            topic = msg.topic

            # Unpack CloudEvents 1.0 envelope or flat JSON contract
            _, payload, event_id = unpack_cloud_event(raw_payload)

            offset_val = getattr(msg, "offset", None)
            offset_str = str(offset_val) if isinstance(offset_val, (int, str)) else ""
            order_key = payload.get("orderNumber") or payload.get("order_number") or ""
            status_key = payload.get("status") or payload.get("orderStatus") or payload.get("eventType") or payload.get("event_type") or ""
            dedup_key = event_id or (f"{topic}:{offset_str}:{order_key}:{status_key}" if offset_str else None)
            if dedup_key and await self._is_durably_processed(dedup_key):
                logger.debug(f"Skipping duplicate event key {dedup_key}")
                return True

            if topic == settings.kafka_orders_topic:
                await self._handle_orders_event(payload)
            elif topic == settings.kafka_fulfillment_topic:
                self._handle_fulfillment_event(payload)

            await self._handle_payment_event(topic, payload)

            # Record deduplication key only AFTER all domain handlers and DB writes succeed
            if dedup_key:
                await self._mark_durably_processed(dedup_key, topic)
            return True
        except Exception:
            logger.exception("Failed to handle Kafka message")
            return False

    async def stop(self):
        if self.consume_task and not self.consume_task.done():
            self.consume_task.cancel()
            await asyncio.gather(self.consume_task, return_exceptions=True)
        if self.consumer and self.is_running:
            self.is_running = False
            await self.consumer.stop()
            logger.info("Kafka Consumer stopped cleanly")


kafka_consumer = AnalyticsKafkaConsumer()
