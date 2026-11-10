import pytest
from langchain_core.messages import HumanMessage
from app.agents.nodes import supervisor_router_node
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
