import pytest
from unittest.mock import AsyncMock, MagicMock
from app.domain.models import FunnelEvent, EventType
from app.infrastructure.repositories import (
    SqlAlchemyFunnelRepository,
    SqlAlchemyAnalyticsStateRepository,
)

@pytest.mark.asyncio
async def test_funnel_repository_save_event():
    mock_session = AsyncMock()
    repo = SqlAlchemyFunnelRepository(mock_session)
    event = FunnelEvent(
        event_type=EventType.CART_ADD,
        category="Electronics",
        step=None,
        session_id="sess-1",
        metadata={"item": "123"},
    )
    saved = await repo.save_event(event)
    assert saved.id == event.id
    mock_session.add.assert_called_once()
    mock_session.commit.assert_awaited_once()

@pytest.mark.asyncio
async def test_funnel_repository_count_events_by_type():
    mock_session = AsyncMock()
    mock_result = MagicMock()
    mock_result.all.return_value = [("CART_ADD", 5), ("CHECKOUT_START", 2)]
    mock_session.execute.return_value = mock_result

    repo = SqlAlchemyFunnelRepository(mock_session)
    counts = await repo.count_events_by_type()
    assert counts == {"CART_ADD": 5, "CHECKOUT_START": 2}

@pytest.mark.asyncio
async def test_analytics_state_repository_record_completed_order():
    mock_session = AsyncMock()
    # 1. Existing order -> skip
    mock_existing_result = MagicMock()
    mock_existing_result.scalar_one_or_none.return_value = MagicMock()
    mock_session.execute.return_value = mock_existing_result

    repo = SqlAlchemyAnalyticsStateRepository(mock_session)
    await repo.record_completed_order("ORD-1", 100.0, "user1", 2)
    mock_session.add.assert_not_called()

    # 2. New order -> save
    mock_session.reset_mock()
    mock_not_existing_result = MagicMock()
    mock_not_existing_result.scalar_one_or_none.return_value = None
    mock_session.execute.return_value = mock_not_existing_result

    await repo.record_completed_order("ORD-2", 150.0, None, None)
    mock_session.add.assert_called_once()
    mock_session.commit.assert_awaited_once()

@pytest.mark.asyncio
async def test_analytics_state_repository_cohort_summary():
    mock_session = AsyncMock()
    row1 = MagicMock(order_count=1, total_spend=50.0)
    row2 = MagicMock(order_count=3, total_spend=200.0)
    row3 = MagicMock(order_count=6, total_spend=500.0)

    mock_result = MagicMock()
    mock_result.all.return_value = [row1, row2, row3]
    mock_session.execute.return_value = mock_result

    repo = SqlAlchemyAnalyticsStateRepository(mock_session)
    summary = await repo.get_cohort_summary()

    assert summary.first_time_orders == 1
    assert summary.first_time_revenue == 50.0
    assert summary.repeat_orders == 3
    assert summary.repeat_revenue == 200.0
    assert summary.loyal_vip_orders == 6
    assert summary.loyal_vip_revenue == 500.0

@pytest.mark.asyncio
async def test_analytics_state_repository_sales_totals():
    mock_session = AsyncMock()
    mock_result1 = MagicMock()
    mock_result1.one.return_value = (10, 1500.0, 25)

    mock_result2 = MagicMock()
    mock_result2.scalars.return_value = [1, 2, 5]

    mock_session.execute.side_effect = [mock_result1, mock_result2]

    repo = SqlAlchemyAnalyticsStateRepository(mock_session)
    totals = await repo.get_sales_totals()

    assert totals["completed_orders"] == 10
    assert totals["total_revenue_usd"] == 1500.0
    assert totals["total_items_sold"] == 25
    assert totals["basket_sizes"] == {
        "single_item": 1,
        "2_3_items": 1,
        "bulk_4_plus": 1,
    }
