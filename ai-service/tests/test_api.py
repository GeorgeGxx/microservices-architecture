import pytest
from httpx import AsyncClient, ASGITransport
from app.main import app


@pytest.mark.asyncio
async def test_health_endpoint():
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as client:
        res = await client.get("/api/health")
        assert res.status_code == 200
        data = res.json()
        assert data["status"] == "healthy"
        assert "layers" in data
        assert "microservices_links" in data["layers"]


@pytest.mark.asyncio
async def test_metrics_endpoint():
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as client:
        res = await client.get("/metrics")
        assert res.status_code == 200
        assert "ai_service_up 1" in res.text


@pytest.mark.asyncio
async def test_tools_endpoint():
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as client:
        res = await client.get("/api/tools")
        assert res.status_code == 200
        data = res.json()
        assert "tools" in data
        tool_names = [t["name"] for t in data["tools"]]
        assert "get_order_details" in tool_names
        assert "check_inventory" in tool_names
        assert "request_refund" in tool_names
        assert "calculate_shipping" in tool_names


@pytest.mark.asyncio
async def test_chat_endpoint_valid():
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as client:
        res = await client.post("/api/chat", json={
            "message": "Where is my package ORD-1001?",
            "thread_id": "test-session-1"
        })
        assert res.status_code == 200
        data = res.json()
        assert "reply" in data
        assert data["active_agent"] == "order_support"


@pytest.mark.asyncio
async def test_chat_endpoint_empty_message_rejected():
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as client:
        res = await client.post("/api/chat", json={
            "message": "   ",
            "thread_id": "test-session-empty"
        })
        assert res.status_code == 400
        assert "cannot be empty" in res.json()["detail"]


@pytest.mark.asyncio
async def test_hitl_approval_and_denial():
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as client:
        res_approve = await client.post("/api/hitl/approve", json={
            "ticket_id": "REF-202611100001",
            "action": "APPROVE",
            "supervisor_notes": "Valid return justification"
        })
        assert res_approve.status_code == 200
        assert res_approve.json()["status"] == "AUTHORIZED"

        res_deny = await client.post("/api/hitl/approve", json={
            "ticket_id": "REF-202611100002",
            "action": "DENY",
            "supervisor_notes": "Exceeded return window"
        })
        assert res_deny.status_code == 200
        assert res_deny.json()["status"] == "DENIED"


@pytest.mark.asyncio
async def test_trigger_evals_endpoint():
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as client:
        res = await client.post("/api/evals/run")
        assert res.status_code == 200
        assert "score_percentage" in res.json()


@pytest.mark.asyncio
async def test_chat_endpoint_security_admin_override(monkeypatch):
    from app.config import settings
    monkeypatch.setattr(settings, "SECURITY_ENABLED", True)
    from app.security import get_current_user
    app.dependency_overrides[get_current_user] = lambda: {
        "roles": ["ROLE_ADMIN"],
        "preferred_username": "operator_admin"
    }

    try:
        async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as client:
            res = await client.post("/api/chat", json={
                "message": "Audit telemetry and system status",
                "thread_id": "test-admin-sec"
            })
            assert res.status_code == 200
            data = res.json()
            assert data["active_agent"] == "admin_operations"
            assert "operator_admin" in data["reply"]
    finally:
        app.dependency_overrides.clear()


@pytest.mark.asyncio
async def test_chat_endpoint_agent_workflow_error(monkeypatch):
    from app.agents.graph import ecommerce_agent_app

    async def mock_ainvoke(*args, **kwargs):
        raise RuntimeError("Synthetic graph pipeline crash")

    monkeypatch.setattr(ecommerce_agent_app, "ainvoke", mock_ainvoke)

    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as client:
        res = await client.post("/api/chat", json={
            "message": "Crash test message",
            "thread_id": "test-crash"
        })
        assert res.status_code == 500
        assert "Agent workflow error" in res.json()["detail"]
