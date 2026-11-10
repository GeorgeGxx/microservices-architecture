import pytest
import json
from app.tools.mcp_server import EcommerceMCPServer
from app.tools.mcp_adapter import (
    get_all_ecommerce_tools,
    get_order_details,
    check_inventory,
    request_refund,
    calculate_shipping
)


@pytest.mark.asyncio
async def test_mcp_check_inventory_known():
    res = await EcommerceMCPServer.call_tool("check_inventory", {"sku": "LAPTOP-PRO"})
    assert res["success"] is True
    assert res["data"]["available"] is True
    assert res["data"]["stock"] > 0


@pytest.mark.asyncio
async def test_mcp_check_inventory_unknown():
    res = await EcommerceMCPServer.call_tool("check_inventory", {"sku": "UNKNOWN-SKU-999"})
    assert res["success"] is True
    assert res["data"]["available"] is False
    assert res["data"]["stock"] == 0


@pytest.mark.asyncio
async def test_mcp_calculate_shipping():
    res_std = await EcommerceMCPServer.call_tool("calculate_shipping", {"dest_zip": "90210", "weight_kg": 1.5})
    assert res_std["success"] is True
    assert res_std["data"]["rates"]["standard"]["cost"] == 5.99

    res_heavy = await EcommerceMCPServer.call_tool("calculate_shipping", {"dest_zip": "10001", "weight_kg": 4.0})
    assert res_heavy["success"] is True
    assert res_heavy["data"]["rates"]["standard"]["cost"] > 5.99


@pytest.mark.asyncio
async def test_mcp_unknown_tool():
    res = await EcommerceMCPServer.call_tool("non_existent_tool", {})
    assert res["success"] is False
    assert "not recognized" in res["error"]


@pytest.mark.asyncio
async def test_mcp_adapter_tools_registered():
    tools = get_all_ecommerce_tools()
    assert len(tools) == 4
    tool_names = [t.name for t in tools]
    assert "get_order_details" in tool_names
    assert "check_inventory" in tool_names
    assert "request_refund" in tool_names
    assert "calculate_shipping" in tool_names


@pytest.mark.asyncio
async def test_mcp_adapter_async_invocation():
    res_order = await get_order_details.ainvoke({"order_id": "ORD-1001"})
    data_order = json.loads(res_order)
    assert data_order["success"] is True

    res_inv = await check_inventory.ainvoke({"sku": "PROD-SONY-WH1000"})
    data_inv = json.loads(res_inv)
    assert data_inv["success"] is True

    res_ref = await request_refund.ainvoke({"order_id": "ORD-1001", "amount": 20.0, "reason": "Wrong item"})
    data_ref = json.loads(res_ref)
    assert data_ref["success"] is True

    res_ship = await calculate_shipping.ainvoke({"dest_zip": "90210", "weight_kg": 2.0})
    data_ship = json.loads(res_ship)
    assert data_ship["success"] is True
