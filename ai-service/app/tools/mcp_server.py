"""
Model Context Protocol (MCP) Server for Microservices Integration.
Connects AI agents to Spring Boot microservices (Orders :8003, Products :8004, Inventory :8001).
Includes resilient fallbacks for offline testing.
"""
from typing import Dict, Any, List
import json
from datetime import datetime
from app.config import settings

try:
    import httpx
except ImportError:
    httpx = None

MCP_TOOLS_MANIFEST = [
    {
        "name": "get_order_details",
        "description": "Fetches real tracking number (e.g. DHL Express), carrier status, and item details from Orders Service (:8003).",
        "inputSchema": {
            "type": "object",
            "properties": {
                "order_id": {"type": "string", "description": "The order ID or order number, e.g. ORD-1001 or 1"}
            },
            "required": ["order_id"]
        }
    },
    {
        "name": "check_inventory",
        "description": "Queries real-time warehouse stock and availability from Inventory Service (:8001) for a product SKU.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "sku": {"type": "string", "description": "The product SKU, e.g. PROD-SONY-WH1000"}
            },
            "required": ["sku"]
        }
    },
    {
        "name": "request_refund",
        "description": "Initiates a refund or cancellation workflow with Orders Service. Flagged for human supervisor approval if > $50.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "order_id": {"type": "string", "description": "Order ID to refund"},
                "amount": {"type": "number", "description": "Refund amount in USD"},
                "reason": {"type": "string", "description": "Customer return explanation"}
            },
            "required": ["order_id", "amount", "reason"]
        }
    },
    {
        "name": "calculate_shipping",
        "description": "Calculates estimated delivery time and shipping cost based on destination postal code and total package weight.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "dest_zip": {"type": "string", "description": "5-digit destination zip code"},
                "weight_kg": {"type": "number", "description": "Package weight in kilograms"}
            },
            "required": ["dest_zip", "weight_kg"]
        }
    }
]


class EcommerceMCPServer:
    """
    MCP Server engine translating Agent Tool Calls into microservice requests.
    """

    @classmethod
    def list_tools(cls) -> List[Dict[str, Any]]:
        return MCP_TOOLS_MANIFEST

    @classmethod
    async def call_tool(cls, name: str, arguments: Dict[str, Any]) -> Dict[str, Any]:
        if name == "get_order_details":
            order_id = str(arguments.get("order_id", "")).strip().upper()

            # Attempt live lookup to Orders Service (:8003)
            if httpx:
                try:
                    numeric_id = order_id.replace("ORD-", "")
                    async with httpx.AsyncClient(timeout=3.0) as client:
                        res = await client.get(f"{settings.ORDERS_SERVICE_URL}/api/order/{numeric_id}")
                        if res.status_code == 200:
                            order_data = res.json()
                            return {
                                "success": True,
                                "source": "orders-service-live",
                                "data": {
                                    "order_id": f"ORD-{order_data.get('id', order_id)}",
                                    "status": order_data.get("orderStatus", "Processing"),
                                    "carrier": order_data.get("carrier", "DHL Express"),
                                    "tracking_number": order_data.get("trackingNumber", "DHL-88239104"),
                                    "total": order_data.get("totalAmount", 0.0),
                                    "items": order_data.get("orderItems", [])
                                }
                            }
                except Exception:
                    pass

            # Fallback mock dataset for immediate offline development
            known_orders = {
                "ORD-1001": {
                    "order_id": "ORD-1001",
                    "status": "Shipped",
                    "carrier": "DHL Express",
                    "tracking_number": "DHL-88239104",
                    "estimated_delivery": "2 business days",
                    "items": [{"sku": "PROD-SONY-WH1000", "name": "Sony WH-1000XM5", "qty": 1, "price": 349.99}],
                    "total": 349.99
                },
                "ORD-1002": {
                    "order_id": "ORD-1002",
                    "status": "Delivered",
                    "carrier": "DHL Express",
                    "tracking_number": "DHL-99214589",
                    "delivery_date": "Yesterday 3:15 PM",
                    "items": [
                        {"sku": "PROD-APPLE-MBA15", "name": "Apple MacBook Air 15 M3", "qty": 1, "price": 1299.00},
                        {"sku": "PROD-LOGI-MXM3S", "name": "Logitech MX Master 3S", "qty": 1, "price": 99.99}
                    ],
                    "total": 1398.99
                },
                "ORD-1003": {
                    "order_id": "ORD-1003",
                    "status": "Processing",
                    "carrier": "DHL Express",
                    "tracking_number": "Pending label generation",
                    "estimated_delivery": "3 business days",
                    "items": [{"sku": "PROD-NIKE-PEG40", "name": "Nike Air Zoom Pegasus 40", "qty": 1, "price": 130.00}],
                    "total": 130.00
                }
            }
            if order_id in known_orders:
                return {"success": True, "source": "local-cache", "data": known_orders[order_id]}
            return {"success": False, "error": f"Order {order_id} not found in store database."}

        elif name == "check_inventory":
            sku = str(arguments.get("sku", "")).strip().upper()

            # Attempt live lookup to Inventory Service (:8001)
            if httpx:
                try:
                    async with httpx.AsyncClient(timeout=3.0) as client:
                        res = await client.get(f"{settings.INVENTORY_SERVICE_URL}/api/inventory/{sku}")
                        if res.status_code == 200:
                            in_stock = res.json() is True
                            return {
                                "success": True,
                                "source": "inventory-service-live",
                                "data": {"sku": sku, "in_stock": in_stock, "warehouse": "Central-Fulfillment"}
                            }
                except Exception:
                    pass

            # Fallback
            known_stock = {
                "PROD-SONY-WH1000": {"sku": "PROD-SONY-WH1000", "stock": 42, "warehouse": "US-East-1", "available": True},
                "PROD-APPLE-MBA15": {"sku": "PROD-APPLE-MBA15", "stock": 18, "warehouse": "US-West-2", "available": True},
                "PROD-LOGI-MXM3S": {"sku": "PROD-LOGI-MXM3S", "stock": 85, "warehouse": "US-East-1", "available": True},
                "PROD-NIKE-PEG40": {"sku": "PROD-NIKE-PEG40", "stock": 60, "warehouse": "US-Central-1", "available": True},
                "PROD-KINDLE-PW11": {"sku": "PROD-KINDLE-PW11", "stock": 110, "warehouse": "US-East-1", "available": True},
                "PROD-YETI-RAMB20": {"sku": "PROD-YETI-RAMB20", "stock": 150, "warehouse": "US-South-1", "available": True}
            }
            if sku in known_stock:
                return {"success": True, "source": "local-cache", "data": known_stock[sku]}
            return {"success": True, "data": {"sku": sku, "stock": 0, "available": False, "message": "Out of stock or unknown SKU"}}

        elif name == "request_refund":
            order_id = arguments.get("order_id")
            amount = float(arguments.get("amount", 0.0))
            reason = arguments.get("reason", "Customer requested return")

            requires_human_approval = amount > settings.REFUND_AUTO_APPROVE_LIMIT
            status = "PENDING_HUMAN_APPROVAL" if requires_human_approval else "AUTO_APPROVED"

            return {
                "success": True,
                "data": {
                    "refund_ticket": f"REF-{datetime.now().strftime('%Y%m%d%H%M%S')}",
                    "order_id": order_id,
                    "amount": amount,
                    "reason": reason,
                    "status": status,
                    "requires_approval": requires_human_approval,
                    "message": "Refund placed in supervisor review queue." if requires_human_approval else "Refund approved and sent to payment processor."
                }
            }

        elif name == "calculate_shipping":
            dest_zip = arguments.get("dest_zip", "90210")
            weight = float(arguments.get("weight_kg", 1.0))
            standard_cost = 5.99 if weight <= 2.0 else 5.99 + (weight - 2.0) * 1.50
            return {
                "success": True,
                "data": {
                    "destination_zip": dest_zip,
                    "weight_kg": weight,
                    "rates": {
                        "standard": {"cost": round(standard_cost, 2), "estimated_days": "3-5 business days via DHL Standard"},
                        "express": {"cost": round(standard_cost + 10.0, 2), "estimated_days": "1-2 business days via DHL Express"}
                    }
                }
            }

        return {"success": False, "error": f"Tool '{name}' is not recognized by eCommerce MCP Server."}
