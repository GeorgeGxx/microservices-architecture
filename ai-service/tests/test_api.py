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

        # Also verify /health root alias
        res_root = await client.get("/health")
        assert res_root.status_code == 200
        assert res_root.json()["status"] == "healthy"


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
    from app.security import get_current_user

    # 1. Default non-supervisor customer identity must be rejected with 403 Forbidden
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as client:
        res_forbidden = await client.post("/api/hitl/approve", json={
            "ticket_id": "REF-202611100001",
            "action": "APPROVE",
            "supervisor_notes": "Attempted approval without supervisor role"
        })
        assert res_forbidden.status_code == 403

    # 2. Authenticated supervisor can approve or deny
    app.dependency_overrides[get_current_user] = lambda: {
        "sub": "sup-1",
        "preferred_username": "supervisor_user",
        "roles": ["ROLE_SUPERVISOR"],
    }
    try:
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
    finally:
        app.dependency_overrides.clear()


@pytest.mark.asyncio
async def test_trigger_evals_endpoint():
    from app.security import get_current_user

    # Non-admin customer is rejected with 403
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as client:
        res_forbidden = await client.post("/api/evals/run")
        assert res_forbidden.status_code == 403

    app.dependency_overrides[get_current_user] = lambda: {
        "sub": "admin-1",
        "preferred_username": "admin_user",
        "roles": ["ROLE_ADMIN"],
    }
    try:
        async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as client:
            res = await client.post("/api/evals/run")
            assert res.status_code == 200
            assert "score_percentage" in res.json()
    finally:
        app.dependency_overrides.clear()


@pytest.mark.asyncio
async def test_security_jwt_and_production_bypass_prevention(monkeypatch):
    import time
    import jwt
    from cryptography.hazmat.primitives.asymmetric import rsa
    from app.config import settings
    from app.security import verify_jwt_token

    # 1. Production environment never allows dev auth bypass even if SECURITY_ENABLED=False
    monkeypatch.setattr(settings, "APP_ENV", "production")
    monkeypatch.setattr(settings, "SECURITY_ENABLED", False)
    assert settings.is_dev_bypass_active() is False

    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as client:
        unauth_chat = await client.post("/api/chat", json={"message": "Hello"})
        assert unauth_chat.status_code == 401

        unauth_hitl = await client.post("/api/hitl/approve", json={"ticket_id": "T-1", "action": "APPROVE"})
        assert unauth_hitl.status_code == 401

    # 2. Verify RS256 cryptographic JWT validation and claim extraction
    private_key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    public_key = private_key.public_key()

    class DummySigningKey:
        key = public_key

    class DummyJWKClient:
        def get_signing_key_from_jwt(self, token):
            return DummySigningKey()

    monkeypatch.setattr("app.security._get_jwk_client", lambda uri: DummyJWKClient())

    now = int(time.time())
    valid_token = jwt.encode(
        {
            "sub": "user-123",
            "preferred_username": "enterprise_supervisor",
            "iss": "http://localhost:8181/realms/microservices-realm",
            "iat": now,
            "exp": now + 300,
            "realm_access": {"roles": ["supervisor", "user"]},
        },
        private_key,
        algorithm="RS256",
    )
    principal = verify_jwt_token(valid_token)
    assert principal["preferred_username"] == "enterprise_supervisor"
    assert "ROLE_SUPERVISOR" in principal["roles"]

    # Expired token must raise 401
    expired_token = jwt.encode(
        {
            "sub": "user-123",
            "iss": "http://localhost:8181/realms/microservices-realm",
            "iat": now - 600,
            "exp": now - 10,
        },
        private_key,
        algorithm="RS256",
    )
    with pytest.raises(Exception) as exc_info:
        verify_jwt_token(expired_token)
    assert getattr(exc_info.value, "status_code", None) == 401

    # Untrusted issuer must raise 401
    bad_issuer_token = jwt.encode(
        {
            "sub": "user-123",
            "iss": "https://evil.example.com/realms/other",
            "iat": now,
            "exp": now + 300,
        },
        private_key,
        algorithm="RS256",
    )
    with pytest.raises(Exception) as exc_info_iss:
        verify_jwt_token(bad_issuer_token)
    assert getattr(exc_info_iss.value, "status_code", None) == 401


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
