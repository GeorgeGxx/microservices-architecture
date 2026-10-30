import json
import pytest
from unittest.mock import AsyncMock, MagicMock, patch
from app.infrastructure.kafka_consumer import AnalyticsKafkaConsumer

@pytest.mark.asyncio
async def test_kafka_consumer_process_payment_message():
    consumer = AnalyticsKafkaConsumer()
    payload = {
        "eventType": "PAYMENT_COMPLETED",
        "order_number": "ORD-12345",
        "amount": 250.0,
        "user_id": "cust-1",
        "items_count": 2,
    }
    raw_msg = MagicMock()
    raw_msg.topic = "payments-topic"
    raw_msg.value = json.dumps(payload).encode("utf-8")

    with patch("app.infrastructure.kafka_consumer.AsyncSessionLocal") as mock_session_cls:
        mock_session = AsyncMock()
        mock_session_cls.return_value.__aenter__.return_value = mock_session

        with patch("app.infrastructure.kafka_consumer.SqlAlchemyAnalyticsStateRepository") as mock_state_cls, \
             patch("app.infrastructure.kafka_consumer.SqlAlchemyFunnelRepository") as mock_funnel_cls:

            mock_state = AsyncMock()
            mock_funnel = AsyncMock()
            mock_state_cls.return_value = mock_state
            mock_funnel_cls.return_value = mock_funnel

            mock_funnel.count_events_by_type.return_value = {"CART_ADD": 10}
            mock_state.get_sales_totals.return_value = {"completed_orders": 8}
            mock_cohort = MagicMock(
                first_time_orders=2, first_time_revenue=100.0,
                repeat_orders=3, repeat_revenue=200.0,
                loyal_vip_orders=1, loyal_vip_revenue=300.0
            )
            mock_state.get_cohort_summary.return_value = mock_cohort

            await consumer._process_message(raw_msg)

            mock_state.record_completed_order.assert_awaited_once_with("ORD-12345", 250.0, "cust-1", 2)
            mock_funnel.save_event.assert_awaited_once()

@pytest.mark.asyncio
async def test_kafka_consumer_process_invalid_message():
    consumer = AnalyticsKafkaConsumer()
    raw_msg = MagicMock()
    raw_msg.topic = "other-topic"
    raw_msg.value = b"invalid json"

    # Should not raise exception
    await consumer._process_message(raw_msg)

@pytest.mark.asyncio
async def test_kafka_consumer_stop():
    consumer = AnalyticsKafkaConsumer()
    consumer.is_running = True
    consumer.consumer = AsyncMock()

    import asyncio
    async def dummy_coro():
        try:
            await asyncio.sleep(10)
        except asyncio.CancelledError:
            pass

    task = asyncio.create_task(dummy_coro())
    consumer.consume_task = task

    await consumer.stop()

    assert task.cancelled() or task.done()
    assert consumer.is_running is False
