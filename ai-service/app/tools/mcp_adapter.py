"""
LangChain Adapter for Model Context Protocol (MCP) Tools.
Translates MCP tool declarations and invocations into LangChain BaseTool objects.
"""
import json
from langchain_core.tools import tool
from pydantic import BaseModel, Field

from app.tools.mcp_server import EcommerceMCPServer


class OrderDetailsInput(BaseModel):
    order_id: str = Field(description="The unique order ID, e.g. ORD-1001 or ORD-1002")


class InventoryInput(BaseModel):
    sku: str = Field(description="Product SKU code, e.g. PROD-SONY-WH1000")


class RefundInput(BaseModel):
    order_id: str = Field(description="Order ID to process refund for")
    amount: float = Field(description="Total refund amount in USD")
    reason: str = Field(description="Reason for refund")


class ShippingInput(BaseModel):
    dest_zip: str = Field(description="5-digit destination postal zip code")
    weight_kg: float = Field(description="Total weight of parcel in kg", default=1.0)


@tool("get_order_details", args_schema=OrderDetailsInput)
async def get_order_details(order_id: str) -> str:
    """Fetches shipping status, carrier, tracking number, and line items for an order."""
    res = await EcommerceMCPServer.call_tool("get_order_details", {"order_id": order_id})
    return json.dumps(res)


@tool("check_inventory", args_schema=InventoryInput)
async def check_inventory(sku: str) -> str:
    """Checks real-time inventory count and fulfillment warehouse location for a product SKU."""
    res = await EcommerceMCPServer.call_tool("check_inventory", {"sku": sku})
    return json.dumps(res)


@tool("request_refund", args_schema=RefundInput)
async def request_refund(order_id: str, amount: float, reason: str) -> str:
    """Initiates a return or refund for an order. Flags approval if amount exceeds policy threshold."""
    res = await EcommerceMCPServer.call_tool("request_refund", {"order_id": order_id, "amount": amount, "reason": reason})
    return json.dumps(res)


@tool("calculate_shipping", args_schema=ShippingInput)
async def calculate_shipping(dest_zip: str, weight_kg: float = 1.0) -> str:
    """Calculates shipping delivery options and rates by destination zip and parcel weight."""
    res = await EcommerceMCPServer.call_tool("calculate_shipping", {"dest_zip": dest_zip, "weight_kg": weight_kg})
    return json.dumps(res)


def get_all_ecommerce_tools():
    return [get_order_details, check_inventory, request_refund, calculate_shipping]
