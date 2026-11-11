import pytest
from langchain_core.messages import HumanMessage
from app.agents.nodes import (
    product_advisor_node,
    order_support_node,
    policy_faq_node,
    general_fallback_node,
)
from app.models.llm_factory import LocalFallbackChatModel, get_chat_model
from app.security import get_current_user, require_role
from app.observability.telemetry import setup_observability
from app.observability.evals import run_evaluations


@pytest.mark.asyncio
async def test_product_advisor_node():
    state = {
        "messages": [HumanMessage(content="Recommend a powerful laptop for coding")],
        "current_agent": "supervisor",
        "hitl_pending": False,
        "tool_calls": [],
        "hitl_payload": None,
        "final_output": None
    }
    res = await product_advisor_node(state)
    assert res["current_agent"] == "product_advisor"
    assert "messages" in res
    assert len(res["messages"]) > 0


@pytest.mark.asyncio
async def test_order_support_node_details():
    state = {
        "messages": [HumanMessage(content="Where is my order ORD-1001?")],
        "current_agent": "supervisor",
        "hitl_pending": False,
        "tool_calls": [],
        "hitl_payload": None,
        "final_output": None
    }
    res = await order_support_node(state)
    assert res["current_agent"] == "order_support"
    assert "DHL" in res["final_output"]


@pytest.mark.asyncio
async def test_order_support_node_unknown_tracking_fdx():
    state = {
        "messages": [HumanMessage(content="Show me status of DHL Tracking FDX-D1D28072")],
        "current_agent": "supervisor",
        "hitl_pending": False,
        "tool_calls": [],
        "hitl_payload": None,
        "final_output": None
    }
    res = await order_support_node(state)
    assert res["current_agent"] == "order_support"
    assert "FDX-D1D28072" in res["final_output"]
    assert "could not find" in res["final_output"].lower()
    assert "Order Status for ORD-1001" not in res["final_output"]
    assert "Sony WH-1000XM5" not in res["final_output"]


@pytest.mark.asyncio
async def test_order_support_node_known_tracking_dhl():
    state = {
        "messages": [HumanMessage(content="Show me status of shipment DHL-88239104")],
        "current_agent": "supervisor",
        "hitl_pending": False,
        "tool_calls": [],
        "hitl_payload": None,
        "final_output": None
    }
    res = await order_support_node(state)
    assert res["current_agent"] == "order_support"
    assert "ORD-1001" in res["final_output"]
    assert "DHL-88239104" in res["final_output"]


@pytest.mark.asyncio
async def test_order_support_node_uuid_order():
    state = {
        "messages": [HumanMessage(content="Where is order 4c5a7ac3-5298-45c1-ba16-6d575e021563?")],
        "current_agent": "supervisor",
        "hitl_pending": False,
        "tool_calls": [],
        "hitl_payload": None,
        "final_output": None
    }
    res = await order_support_node(state)
    assert res["current_agent"] == "order_support"
    assert "4c5a7ac3-5298-45c1-ba16-6d575e021563" in res["final_output"]


@pytest.mark.asyncio
async def test_order_support_node_missing_order_id():
    state = {
        "messages": [HumanMessage(content="Can you track my package?")],
        "current_agent": "supervisor",
        "hitl_pending": False,
        "tool_calls": [],
        "hitl_payload": None,
        "final_output": None
    }
    res = await order_support_node(state)
    assert res["current_agent"] == "order_support"
    assert "Please provide your" in res["final_output"]


@pytest.mark.asyncio
async def test_order_support_node_refund_missing_order_id():
    state = {
        "messages": [HumanMessage(content="I want a refund for my item")],
        "current_agent": "supervisor",
        "hitl_pending": False,
        "tool_calls": [],
        "hitl_payload": None,
        "final_output": None
    }
    res = await order_support_node(state)
    assert res["current_agent"] == "order_support"
    assert "Order ID" in res["final_output"]
    assert res["hitl_pending"] is False


@pytest.mark.asyncio
async def test_order_support_node_refund_with_tracking_number():
    state = {
        "messages": [HumanMessage(content="I want to refund $25.00 for tracking DHL-88239104")],
        "current_agent": "supervisor",
        "hitl_pending": False,
        "tool_calls": [],
        "hitl_payload": None,
        "final_output": None
    }
    res = await order_support_node(state)
    assert res["current_agent"] == "order_support"
    assert "ORD-1001" in res["final_output"]
    assert "automatically approved" in res["final_output"]


@pytest.mark.asyncio
async def test_order_support_node_auto_refund():
    state = {
        "messages": [HumanMessage(content="Request a refund of $30.00 for order ORD-1001")],
        "current_agent": "supervisor",
        "hitl_pending": False,
        "tool_calls": [],
        "hitl_payload": None,
        "final_output": None
    }
    res = await order_support_node(state)
    assert res["current_agent"] == "order_support"
    assert res["hitl_pending"] is False
    assert "automatically approved" in res["final_output"]


@pytest.mark.asyncio
async def test_policy_faq_node():
    state = {
        "messages": [HumanMessage(content="What is the return window and warranty policy?")],
        "current_agent": "supervisor",
        "hitl_pending": False,
        "tool_calls": [],
        "hitl_payload": None,
        "final_output": None
    }
    res = await policy_faq_node(state)
    assert res["current_agent"] == "policy_faq"
    assert "messages" in res


@pytest.mark.asyncio
async def test_general_fallback_node():
    state = {
        "messages": [HumanMessage(content="Hello there! Tell me what you can do.")],
        "current_agent": "supervisor",
        "hitl_pending": False,
        "tool_calls": [],
        "hitl_payload": None,
        "final_output": None
    }
    res = await general_fallback_node(state)
    assert res["current_agent"] == "general_assistant"


def test_local_fallback_chat_model_variations():
    model = LocalFallbackChatModel()

    res_order = model.invoke([HumanMessage(content="Where is order ORD-1001?")])
    assert "DHL" in res_order.content

    res_refund = model.invoke([HumanMessage(content="I want a refund for my purchase")])
    assert "30 days" in res_refund.content

    res_prod = model.invoke([HumanMessage(content="Recommend a laptop or headphones")])
    assert "MacBook" in res_prod.content

    res_gen = model.invoke([HumanMessage(content="Good morning!")])
    assert "AuraCommerce AI Copilot" in res_gen.content

    assert model._llm_type == "local-fallback-chat-model"


def test_get_chat_model():
    model = get_chat_model(temperature=0.5)
    assert model is not None


from unittest.mock import patch, AsyncMock, MagicMock
from fastapi import HTTPException
from fastapi.security import HTTPAuthorizationCredentials
from app.config import settings
from app.models.llm_factory import ensure_ollama_model_installed
from app.tools.mcp_server import EcommerceMCPServer


def test_security_utilities():
    user = get_current_user(None)
    assert user["sub"] == "dev-user"
    assert "ROLE_ADMIN" in user["roles"]

    checker = require_role("ROLE_SUPERVISOR")
    res = checker(user)
    assert res == user


def test_security_enabled_enforcement(monkeypatch):
    monkeypatch.setattr(settings, "SECURITY_ENABLED", True)
    # 1. Missing credentials triggers 401
    with pytest.raises(HTTPException) as exc_info_401:
        get_current_user(None)
    assert exc_info_401.value.status_code == 401

    # 2. Valid credentials returns user dict
    creds = HTTPAuthorizationCredentials(scheme="Bearer", credentials="jwt-sample-token")
    authed_user = get_current_user(creds)
    assert authed_user["token"] == "jwt-sample-token"
    assert "ROLE_USER" in authed_user["roles"]

    # 3. Insufficient role triggers 403
    supervisor_checker = require_role("ROLE_SUPERVISOR")
    with pytest.raises(HTTPException) as exc_info_403:
        supervisor_checker(authed_user)
    assert exc_info_403.value.status_code == 403

    # 4. Matching role or ROLE_ADMIN passes
    user_checker = require_role("ROLE_USER")
    assert user_checker(authed_user) == authed_user

    admin_user = {"sub": "admin", "roles": ["ROLE_ADMIN"]}
    assert supervisor_checker(admin_user) == admin_user


@pytest.mark.asyncio
async def test_ensure_ollama_model_installed_unreachable():
    # Gracefully catches connection error and logs notice
    await ensure_ollama_model_installed("http://127.0.0.1:59999", "llama3.1:8b")


@pytest.mark.asyncio
async def test_ensure_ollama_model_installed_mocked_success():
    # Mocking installed model
    mock_tags_response = MagicMock()
    mock_tags_response.status_code = 200
    mock_tags_response.json.return_value = {"models": [{"name": "llama3.1:8b"}]}

    with patch("httpx.AsyncClient.get", new_callable=AsyncMock) as mock_get:
        mock_get.return_value = mock_tags_response
        await ensure_ollama_model_installed("http://mock-ollama:11434", "llama3.1:8b")

    # Mocking uninstalled model and pull
    mock_empty_tags = MagicMock()
    mock_empty_tags.status_code = 200
    mock_empty_tags.json.return_value = {"models": []}

    mock_pull_response = MagicMock()
    mock_pull_response.status_code = 200

    with patch("httpx.AsyncClient.get", new_callable=AsyncMock) as mock_get_empty, \
         patch("httpx.AsyncClient.post", new_callable=AsyncMock) as mock_post_pull:
        mock_get_empty.return_value = mock_empty_tags
        mock_post_pull.return_value = mock_pull_response
        await ensure_ollama_model_installed("http://mock-ollama:11434", "deepseek-coder:6.7b")


def test_local_fallback_chat_model_list_content():
    model = LocalFallbackChatModel()
    res = model.invoke([HumanMessage(content=[{"type": "text", "text": "Where is my order ORD-1002"}])])
    assert "DHL" in res.content


def test_get_chat_model_provider_branches(monkeypatch):
    monkeypatch.setattr(settings, "LLM_PROVIDER", "ollama")
    model_ollama = get_chat_model()
    assert model_ollama is not None

    monkeypatch.setattr(settings, "LLM_PROVIDER", "openai")
    model_openai = get_chat_model()
    assert model_openai is not None


@pytest.mark.asyncio
async def test_mcp_unfound_order_and_supervisor_threshold():
    res_unknown = await EcommerceMCPServer.call_tool("get_order_details", {"order_id": "ORD-UNKNOWN-999"})
    assert res_unknown["success"] is False
    assert "not found" in res_unknown["error"]

    res_threshold = await EcommerceMCPServer.call_tool("request_refund", {
        "order_id": "ORD-1001",
        "amount": 250.00,
        "reason": "Damaged goods"
    })
    assert res_threshold["success"] is True
    assert res_threshold["data"]["requires_approval"] is True
    assert res_threshold["data"]["status"] == "PENDING_HUMAN_APPROVAL"


def test_config_defaults():
    assert settings.PORT == 8010
    assert "AuraCommerce" in settings.APP_NAME
    assert settings.REFUND_AUTO_APPROVE_LIMIT == 50.0


def test_telemetry_setup_no_crash(monkeypatch):
    setup_observability()
    monkeypatch.setattr(settings, "ENABLE_OBSERVABILITY", True)
    setup_observability()


@pytest.mark.asyncio
async def test_run_evaluations():
    summary = await run_evaluations()
    assert summary["total_evals"] == 4
    assert summary["passed"] >= 3
