from types import SimpleNamespace
from unittest.mock import AsyncMock, MagicMock

import pytest

from app import main


class DatabaseContext:
    async def __aenter__(self):
        return self

    async def __aexit__(self, *_):
        return False

    async def run_sync(self, _operation):
        return None


class SessionContext:
    def __init__(self, session):
        self.session = session

    async def __aenter__(self):
        return self.session

    async def __aexit__(self, *_):
        return False


def _query_result(*, rows=None, scalar=None):
    result = MagicMock()
    result.scalars.return_value.all.return_value = rows or []
    result.scalar.return_value = scalar
    return result


@pytest.mark.asyncio
async def test_lifespan_retries_database_startup_and_hydrates_metrics(monkeypatch):
    begin = MagicMock(side_effect=[RuntimeError("database starting"), DatabaseContext()])
    engine = SimpleNamespace(begin=begin, dispose=AsyncMock())
    monkeypatch.setattr(main, "engine", engine)
    sleep = AsyncMock()
    monkeypatch.setattr(main.asyncio, "sleep", sleep)

    session = MagicMock()
    session.execute = AsyncMock(return_value=_query_result(scalar=0))
    monkeypatch.setattr(main, "AsyncSessionLocal", lambda: SessionContext(session))

    state_repo = MagicMock()
    state_repo.get_sales_totals = AsyncMock(return_value={"completed_orders": 3, "total_revenue_usd": 120.5})
    state_repo.get_cohort_summary = AsyncMock(return_value=SimpleNamespace(
        first_time_orders=1, repeat_orders=2, loyal_vip_orders=0,
        first_time_revenue=20.5, repeat_revenue=100.0, loyal_vip_revenue=0.0,
    ))
    state_repo.get_sku_sales = AsyncMock(return_value={"SKU-1": 4})
    funnel_repo = MagicMock()
    funnel_repo.count_events_by_type = AsyncMock(return_value={"CART_ADD": 6, "CHECKOUT_START": 3, "CHECKOUT_STEP": 2})
    monkeypatch.setattr(main, "SqlAlchemyAnalyticsStateRepository", lambda _session: state_repo)
    monkeypatch.setattr(main, "SqlAlchemyFunnelRepository", lambda _session: funnel_repo)
    monkeypatch.setattr(main.kafka_consumer, "start", AsyncMock())
    monkeypatch.setattr(main.kafka_consumer, "stop", AsyncMock())

    async with main.lifespan(main.app):
        main.kafka_consumer.start.assert_awaited_once()

    assert begin.call_count == 2
    sleep.assert_awaited_once_with(2)
    state_repo.get_sku_sales.assert_awaited_once()
    main.kafka_consumer.stop.assert_awaited_once()
    engine.dispose.assert_awaited_once()


@pytest.mark.asyncio
async def test_lifespan_seeds_baseline_funnel_when_persistent_data_is_sparse(monkeypatch):
    engine = SimpleNamespace(begin=MagicMock(return_value=DatabaseContext()), dispose=AsyncMock())
    monkeypatch.setattr(main, "engine", engine)
    session = MagicMock()
    session.execute = AsyncMock(side_effect=[_query_result(rows=[]), _query_result(scalar=0)])
    monkeypatch.setattr(main, "AsyncSessionLocal", lambda: SessionContext(session))

    state_repo = MagicMock()
    state_repo.get_sales_totals = AsyncMock(return_value={"completed_orders": 0, "total_revenue_usd": 0})
    state_repo.get_cohort_summary = AsyncMock(return_value=SimpleNamespace(
        first_time_orders=0, repeat_orders=0, loyal_vip_orders=0,
        first_time_revenue=0.0, repeat_revenue=0.0, loyal_vip_revenue=0.0,
    ))
    state_repo.get_sku_sales = AsyncMock(return_value={})
    funnel_repo = MagicMock()
    funnel_repo.count_events_by_type = AsyncMock(side_effect=[{"CART_ADD": 0}, {"CART_ADD": 12, "CHECKOUT_START": 2, "CHECKOUT_STEP": 0}])
    funnel_repo.save_event = AsyncMock()
    monkeypatch.setattr(main, "SqlAlchemyAnalyticsStateRepository", lambda _session: state_repo)
    monkeypatch.setattr(main, "SqlAlchemyFunnelRepository", lambda _session: funnel_repo)
    monkeypatch.setattr(main.kafka_consumer, "start", AsyncMock())
    monkeypatch.setattr(main.kafka_consumer, "stop", AsyncMock())

    async with main.lifespan(main.app):
        pass

    assert funnel_repo.save_event.await_count == 14
    assert funnel_repo.count_events_by_type.await_count == 2
    main.kafka_consumer.stop.assert_awaited_once()
    engine.dispose.assert_awaited_once()
