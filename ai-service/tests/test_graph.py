import pytest
from langchain_core.messages import HumanMessage
from app.agents.nodes import supervisor_router_node
from app.agents.graph import route_decision, ecommerce_agent_app
from app.tools.mcp_server import EcommerceMCPServer


def test_supervisor_order_intent_routing():
    state = {
        "messages": [HumanMessage(content="Where is my package ORD-1001 shipped via DHL?")],
        "current_agent": "supervisor",
        "hitl_pending": False,
        "tool_calls": [],
        "hitl_payload": None,
        "final_output": None
    }
    res = supervisor_router_node(state)
    assert res["detected_intent"] == "order_support"


def test_supervisor_catalog_intent_routing():
    state = {
        "messages": [HumanMessage(content="Recommend a powerful laptop for design and programming")],
        "current_agent": "supervisor",
        "hitl_pending": False,
        "tool_calls": [],
        "hitl_payload": None,
        "final_output": None
    }
    res = supervisor_router_node(state)
    assert res["detected_intent"] == "catalog"


@pytest.mark.asyncio
async def test_mcp_get_order_tool():
    res = await EcommerceMCPServer.call_tool("get_order_details", {"order_id": "ORD-1001"})
    assert res["success"] is True
    assert res["data"]["carrier"] == "DHL Express"


@pytest.mark.asyncio
async def test_hitl_refund_threshold_triggers():
    res_high = await EcommerceMCPServer.call_tool("request_refund", {
        "order_id": "ORD-1002",
        "amount": 120.00,
        "reason": "Return request"
    })
    assert res_high["data"]["requires_approval"] is True
    assert res_high["data"]["status"] == "PENDING_HUMAN_APPROVAL"

    res_low = await EcommerceMCPServer.call_tool("request_refund", {
        "order_id": "ORD-1003",
        "amount": 25.00,
        "reason": "Missing cable"
    })
    assert res_low["data"]["requires_approval"] is False
    assert res_low["data"]["status"] == "AUTO_APPROVED"


def test_route_decision_branches():
    assert route_decision({"detected_intent": "catalog"}) == "product_advisor"
    assert route_decision({"detected_intent": "order_support"}) == "order_support"
    assert route_decision({"detected_intent": "policy_faq"}) == "policy_faq"
    assert route_decision({"detected_intent": "admin_ops"}) == "admin_ops"
    assert route_decision({"detected_intent": "unknown_intent"}) == "general_fallback"
    assert route_decision({}) == "general_fallback"


@pytest.mark.asyncio
async def test_ecommerce_agent_app_compiled():
    assert ecommerce_agent_app is not None
    config = {"configurable": {"thread_id": "test-graph-compiled"}}
    res = await ecommerce_agent_app.ainvoke({
        "messages": [HumanMessage(content="Hello AI")],
        "user_role": "customer",
        "username": "user1"
    }, config=config)
    assert res is not None
    assert "messages" in res
    assert res.get("final_output") is not None
