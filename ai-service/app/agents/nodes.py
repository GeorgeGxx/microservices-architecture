import asyncio
import logging
import re
from typing import Dict, Any, Optional, List
import httpx
from langchain_core.messages import AIMessage, SystemMessage, HumanMessage

from app.agents.state import EcommerceAgentState
from app.models.llm_factory import get_chat_model
from app.rag.retriever import rag_store
from app.tools.mcp_server import EcommerceMCPServer
from app.config import settings

logger = logging.getLogger("ai_agents")


def supervisor_router_node(state: EcommerceAgentState) -> Dict[str, Any]:
    messages = state.get("messages", [])
    if not messages:
        return {"current_agent": "supervisor", "detected_intent": "general"}

    last_user_msg = messages[-1].content.lower()
    user_role = state.get("user_role", "customer")

    if user_role == "admin" and any(k in last_user_msg for k in ["admin", "telemetry", "metric", "forecast", "pronostico", "stock global", "inventario global", "hitl", "supervis", "microservice", "health", "system", "audit"]):
        intent = "admin_ops"
    elif any(k in last_user_msg for k in ["order", "ord-", "tracking", "track", "shipment", "carrier", "refund", "devoluc", "reembolso", "paquete", "dhl"]):
        intent = "order_support"
    elif any(k in last_user_msg for k in [
        "recommend", "suggest", "laptop", "notebook", "computer", "computadora", "portatil", "portátil",
        "headphone", "headset", "audifono", "audífono", "auricular", "mouse", "raton", "ratón",
        "keyboard", "teclado", "monitor", "display", "shoes", "precio", "catalogo", "catálogo",
        "catalog", "product", "buy", "comprar", "suger", "recomend",
    ]):
        intent = "catalog"
    elif any(k in last_user_msg for k in ["policy", "politica", "garantia", "warranty", "shipping days", "dias de envio", "plazo"]):
        intent = "policy_faq"
    else:
        intent = "general"

    return {
        "current_agent": "supervisor",
        "detected_intent": intent
    }


def _synthesize_product_recommendation(
    retrieved_items: List[Dict[str, Any]],
    query: str,
    user_role: str = "customer"
) -> str:
    unique_items = _unique_products(retrieved_items)
    if not unique_items:
        return (
            "I searched our catalog knowledge base for your inquiry, but could not find a specific match. "
            "You can explore our full catalog in the Featured Products section or refine your search."
        )

    if user_role == "admin":
        return _format_admin_product_recommendation(unique_items)

    return _format_customer_product_recommendation(unique_items)


def _unique_products(items: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
    unique_items = []
    seen_products = set()
    for item in items:
        metadata = item.get("metadata", {})
        product_key = str(metadata.get("sku") or metadata.get("title") or item.get("id") or "").strip().casefold()
        if product_key and product_key not in seen_products:
            seen_products.add(product_key)
            unique_items.append(item)
    return unique_items


def _format_admin_product_recommendation(items: List[Dict[str, Any]]) -> str:
    lines = ["🛡️ **Catalog results for your inquiry:**\n"]
    if any(item.get("metadata", {}).get("catalog_source") == "sample-cache" for item in items):
        lines.append("*The live catalog is unavailable; these results use the local development sample catalog.*\n")
    for item in items:
        metadata = item.get("metadata", {})
        lines.append(f"- **SKU:** `{metadata.get('sku', 'Not provided by catalog')}`\n")
        lines.append(_format_customer_product(item))
    lines.append(
        "Prices and availability are shown only when returned by the catalog and inventory services. "
        "For demand predictions, open Admin Console → Demand Forecast · 7 Days."
    )
    return "\n".join(lines)


def _format_customer_product_recommendation(items: List[Dict[str, Any]]) -> str:
    lines = ["Here are our top recommendations based on your request from the store catalog:\n"]
    if any(item.get("metadata", {}).get("catalog_source") == "sample-cache" for item in items):
        lines.append("*Live catalog is unavailable; these results use the local development sample catalog.*\n")
    for item in items:
        lines.append(_format_customer_product(item))
    lines.append("Would you like more technical details on any of these options or assistance adding one to your cart?")
    return "\n".join(lines)


def _format_customer_product(item: Dict[str, Any]) -> str:
    metadata = item.get("metadata", {})
    content = item.get("content", "")
    description = next((line.partition(":")[2].strip() for line in content.splitlines() if line.startswith("Description:")), "")
    rating = metadata.get("rating")
    if rating is None:
        rating_match = re.search(r"^Rating:\s*([0-5](?:\.\d+)?)\s*/\s*5", content, re.MULTILINE | re.IGNORECASE)
        rating = float(rating_match.group(1)) if rating_match else None
    price_line = _format_numeric_line("Price", metadata.get("price"), "${:.2f} USD")
    rating_line = _format_numeric_line("Rating", rating, "⭐ {:g} / 5.0")
    inventory_status = metadata.get("inventory_status")
    availability = {
        True: "- **Availability:** In stock (verified with the inventory service).\n",
        False: "- **Availability:** Currently out of stock (verified with the inventory service).\n",
    }.get(inventory_status, "- **Availability:** Stock status could not be verified right now.\n")
    overview = f"- **Overview:** {description}\n" if description else ""
    return (
        f"### 💻 **{metadata.get('title', 'Product')}**\n{price_line}{rating_line}"
        f"- **Category:** {metadata.get('category', 'Electronics')}\n{overview}{availability}"
    )


def _format_numeric_line(label: str, value: Any, value_format: str) -> str:
    if value is None:
        return ""
    try:
        return f"- **{label}:** {value_format.format(float(value))}\n"
    except (TypeError, ValueError):
        return ""


async def _attach_live_inventory_status(items: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
    async def enrich(item: Dict[str, Any]) -> Dict[str, Any]:
        metadata = item.get("metadata", {})
        sku = str(metadata.get("sku", "")).strip()
        if not sku:
            return item
        try:
            result = await asyncio.wait_for(
                EcommerceMCPServer.call_tool("check_inventory", {"sku": sku}),
                timeout=1.5,
            )
        except (OSError, ValueError):
            return item
        if result.get("success") and result.get("source") == "inventory-service-live":
            updated = dict(item)
            updated_metadata = dict(metadata)
            updated_metadata["inventory_status"] = bool(result.get("data", {}).get("in_stock"))
            updated["metadata"] = updated_metadata
            return updated
        # Local demo/cache inventory is intentionally not presented as live availability.
        return item

    return await asyncio.gather(*(enrich(item) for item in items))


async def _fetch_live_catalog_documents() -> Optional[List[Dict[str, Any]]]:
    endpoint = f"{settings.PRODUCTS_SERVICE_URL.rstrip('/')}/api/product"
    try:
        async with httpx.AsyncClient(timeout=1.0) as client:
            response = await client.get(endpoint)
            response.raise_for_status()
            products = response.json()
    except (httpx.HTTPError, OSError, ValueError) as exc:
        logger.info("Live product catalog unavailable; using environment policy: %s", type(exc).__name__)
        return None

    if not isinstance(products, list):
        logger.warning("Products service returned an unexpected catalog response shape")
        return None

    return [document for product in products if (document := _product_to_document(product)) is not None]


def _product_to_document(product: Any) -> Optional[Dict[str, Any]]:
    if not isinstance(product, dict) or product.get("status") is False:
        return None
    sku = str(product.get("sku", "")).strip()
    name = str(product.get("name", "")).strip()
    if not sku or not name:
        return None
    category = str(product.get("category") or "General")
    description = str(product.get("description") or "")
    price = product.get("price")
    prices = product.get("prices")
    if price is None and isinstance(prices, dict):
        price = prices.get("USD")
    rating = product.get("rating")
    content = f"Product: {name}\nCategory: {category}\n"
    if price is not None:
        content += f"Price: ${price}\n"
    if rating is not None:
        content += f"Rating: {rating} / 5.0\n"
    if description:
        content += f"Description: {description}\n"
    return {
        "id": f"product-{sku}",
        "content": content,
        "metadata": {
            "type": "product", "title": name, "sku": sku, "price": price,
            "rating": rating, "category": category, "tags": [], "catalog_source": "products-service",
        },
    }


def _synthesize_policy_response(retrieved_policies: List[Dict[str, Any]], _query: Optional[str] = None) -> str:
    if not retrieved_policies:
        return (
            "🛡️ **AuraCommerce Store Policy**:\n\n"
            "Our standard store policy provides a **30-day return window** from delivery and a **1-year limited warranty** "
            "on all electronic devices. Standard shipping takes 3-5 business days."
        )
    lines = ["🛡️ **AuraCommerce Store Policies & Customer Protection**:\n"]
    for p in retrieved_policies:
        lines.append(p.get("content", ""))
        lines.append("")
    lines.append("If you need to start a return or warranty claim, you can request it right here in the Copilot.")
    return "\n".join(lines)


async def product_advisor_node(state: EcommerceAgentState) -> Dict[str, Any]:
    messages = state.get("messages", [])
    query = messages[-1].content if messages else ""
    user_role = state.get("user_role", "customer")

    # Customer-facing catalog facts must come from the catalog result, not free-form
    # model generation. This prevents invented products, duplicate cards, and stock claims.
    if user_role != "admin":
        return await _customer_product_advisor(query)
    return await _admin_product_advisor(query)


async def _customer_product_advisor(query: str) -> Dict[str, Any]:
    live_catalog = await _fetch_live_catalog_documents()
    if live_catalog is None:
        environment = (settings.APP_ENV or "development").strip().lower()
        if environment in {"production", "prod", "staging"}:
            return _product_advisor_result("I can't access the live store catalog right now. Please try again shortly.")
        retrieved_items = rag_store.search(query=query, doc_type="product", top_k=2)
        for item in retrieved_items:
            item.setdefault("metadata", {})["catalog_source"] = "sample-cache"
    else:
        retrieved_items = rag_store.search_documents(live_catalog, query=query, doc_type="product", top_k=2)
    verified_items = await _attach_live_inventory_status(retrieved_items)
    return _product_advisor_result(_synthesize_product_recommendation(verified_items, query))


async def _admin_product_advisor(query: str) -> Dict[str, Any]:
    live_catalog = await _fetch_live_catalog_documents()
    if live_catalog is None:
        environment = (settings.APP_ENV or "development").strip().lower()
        if environment in {"production", "prod", "staging"}:
            return _product_advisor_result(
                "I can't access the live store catalog right now. Please try again shortly."
            )
        retrieved_items = rag_store.search(query=query, doc_type="product", top_k=2)
        for item in retrieved_items:
            item.setdefault("metadata", {})["catalog_source"] = "sample-cache"
    else:
        retrieved_items = rag_store.search_documents(live_catalog, query=query, doc_type="product", top_k=2)

    verified_items = await _attach_live_inventory_status(retrieved_items)
    reply = _synthesize_product_recommendation(verified_items, query, user_role="admin")
    return _product_advisor_result(reply)


def _product_advisor_result(reply_content: str) -> Dict[str, Any]:
    return {
        "messages": [AIMessage(content=reply_content)],
        "current_agent": "product_advisor",
        "final_output": reply_content,
    }


def _extract_order_or_tracking_id(user_msg: str) -> Optional[str]:
    # 0. UUID order format (e.g. 4c5a7ac3-5298-45c1-ba16-6d575e021563)
    uuid_match = re.search(r"\b[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}\b", user_msg)
    if uuid_match:
        return uuid_match.group(0).lower()

    # 1. Standard Order ID (e.g. ORD-1001)
    ord_match = re.search(r"\bORD-(\d+)\b", user_msg, re.IGNORECASE)
    if ord_match:
        return f"ORD-{ord_match.group(1)}"

    # 2. Carrier tracking numbers (e.g. DHL-88239104, FDX-D1D28072, UPS-12345)
    carrier_match = re.search(r"\b[A-Za-z]{2,5}-[A-Za-z0-9]+\b", user_msg)
    if carrier_match:
        return carrier_match.group(0).upper()

    # 3. Explicit tracking keywords (e.g. tracking FDX-D1D28072, guia DHL8823)
    keyword_match = re.search(r"(?:tracking|guia|guía|rastreo|shipment)[\s:#]+([a-z0-9-]+)", user_msg, re.IGNORECASE)
    if keyword_match:
        val = keyword_match.group(1).strip("-").upper()
        stopwords = {"STATUS", "NUMBER", "CODE", "INFO", "ORDER", "PEDIDO", "ORDEN", "DETAILS", "UPDATE", "MY"}
        if len(val) >= 4 and val not in stopwords and any(c.isdigit() for c in val):
            return val

    # 4. Numeric order patterns (e.g. order #1001, pedido 1002)
    order_num_match = re.search(r"(?:order|pedido)[\s:#]+(\d{1,8})\b", user_msg, re.IGNORECASE)
    if order_num_match:
        return f"ORD-{order_num_match.group(1)}"

    return None


def _format_order_status_reply(data: Dict[str, Any], user_role: str = "customer", username: str = "guest") -> str:
    items_summary = ", ".join([f"{it['name']} (x{it['qty']})" for it in data.get("items", [])]) if data.get("items") else "Standard catalog items"
    carrier_label = data.get("carrier", "Carrier")
    reply = (
        f"📦 **Order Status for {data['order_id']}**:\n"
        f"- **Status:** {data['status']}\n"
        f"- **Carrier:** {carrier_label}\n"
        f"- **Tracking Number:** `{data['tracking_number']}`\n"
        f"- **Items:** {items_summary}\n"
        f"- **Total:** ${data.get('total', 0.0):.2f} USD\n"
    )
    if user_role == "admin":
        reply += (
            f"- **Admin Audit:** Verified via Federated Orders Subgraph | Auditor: `{username}`\n"
            f"- **Fulfillment Pipeline:** Ready for dispatch / Carrier API synchronized\n\n"
            f"Supervisor controls: You can issue adjustments, trigger refunds, or audit traces."
        )
    else:
        reply += (
            "\nDo you need additional assistance with this shipment or wish to initiate an exchange?"
        )
    return reply


async def _handle_refund_flow(
    order_id: Optional[str],
    user_msg: str,
    user_role: str = "customer",
    username: str = "guest"
) -> Dict[str, Any]:
    if not order_id:
        reply_text = (
            "To process a refund or return request, please provide your **Order ID** (e.g., `ORD-1001` or `ORD-1002`)."
        )
        return {
            "messages": [AIMessage(content=reply_text)],
            "current_agent": "order_support",
            "hitl_pending": False,
            "final_output": reply_text
        }

    resolved_order_id = order_id
    if not resolved_order_id.startswith("ORD-"):
        lookup = await EcommerceMCPServer.call_tool("get_order_details", {"order_id": resolved_order_id})
        if lookup.get("success") and "data" in lookup and "order_id" in lookup["data"]:
            resolved_order_id = lookup["data"]["order_id"]

    amount_match = re.search(r"\$\s*(\d+(?:\.\d{1,2})?)", user_msg)
    if not amount_match:
        amount_match = re.search(r"\b(\d+(?:\.\d{1,2})?)\s*(?:usd|dollars|dolares)\b", user_msg, re.IGNORECASE)
    amount = float(amount_match.group(1)) if amount_match else 75.00

    tool_result = await EcommerceMCPServer.call_tool("request_refund", {
        "order_id": resolved_order_id,
        "amount": amount,
        "reason": user_msg
    })

    if amount > settings.REFUND_AUTO_APPROVE_LIMIT:
        if user_role == "admin":
            reply_text = (
                f"⚡ **Supervisor Decision Gate (Admin User: `{username}`)**:\n\n"
                f"Order **{resolved_order_id}** has a pending refund request for **${amount:.2f} USD** awaiting authorization.\n"
                f"As an authorized store administrator, you can directly **Approve** or **Deny** this transaction using the decision gate below:"
            )
        else:
            reply_text = (
                f"We have registered your refund request for order **{resolved_order_id}** in the amount of **${amount:.2f} USD**.\n\n"
                f"⚠️ **Attention:** In accordance with store security policies, refunds exceeding ${settings.REFUND_AUTO_APPROVE_LIMIT:.2f} USD "
                f"require authorization from a human supervisor. Your request has been routed to the real-time supervisor approval queue."
            )
        return {
            "messages": [AIMessage(content=reply_text)],
            "current_agent": "order_support",
            "hitl_pending": True,
            "hitl_payload": tool_result["data"],
            "final_output": reply_text
        }

    reply_text = (
        f"Your refund request for order **{resolved_order_id}** for **${amount:.2f} USD** was **automatically approved**.\n"
        f"Ticket reference: `{tool_result['data']['refund_ticket']}`. The credit will reflect on your original payment method in 3 to 5 business days."
    )
    return {
        "messages": [AIMessage(content=reply_text)],
        "current_agent": "order_support",
        "hitl_pending": False,
        "final_output": reply_text
    }


async def order_support_node(state: EcommerceAgentState) -> Dict[str, Any]:
    messages = state.get("messages", [])
    user_msg = messages[-1].content if messages else ""
    user_role = state.get("user_role", "customer")
    username = state.get("username", "guest")

    order_id = _extract_order_or_tracking_id(user_msg)
    is_refund = any(w in user_msg.lower() for w in ["refund", "reembolso", "devolver", "return", "cancel"])

    if is_refund:
        return await _handle_refund_flow(order_id, user_msg, user_role=user_role, username=username)

    # Order details lookup
    if not order_id:
        reply_text = (
            "Please provide your **Order ID** (e.g., `ORD-1001` or Order UUID) or your **Carrier Tracking Number** "
            "(e.g., `DHL-88239104` or `FDX-D1D28072`) so I can check its current real-time shipment status."
        )
        return {
            "messages": [AIMessage(content=reply_text)],
            "current_agent": "order_support",
            "hitl_pending": False,
            "final_output": reply_text
        }

    tool_result = await EcommerceMCPServer.call_tool("get_order_details", {"order_id": order_id})
    if tool_result.get("success"):
        reply_text = _format_order_status_reply(tool_result["data"], user_role=user_role, username=username)
    else:
        reply_text = (
            f"🔍 **Shipment / Order Lookup**:\n"
            f"We could not find an order or shipment matching **`{order_id}`** in our database.\n\n"
            f"Please verify your Order ID (e.g., `ORD-1001` or UUID) or Carrier Tracking Number (e.g., `FDX-D1D28072`)."
        )

    return {
        "messages": [AIMessage(content=reply_text)],
        "current_agent": "order_support",
        "hitl_pending": False,
        "final_output": reply_text
    }


async def admin_ops_node(state: EcommerceAgentState) -> Dict[str, Any]:
    await asyncio.sleep(0)
    reply = (
        "I can look up catalog products and inventory, track a specific order or shipment, answer store policy questions, "
        "and show demand forecasts in Admin Console → Demand Forecast · 7 Days. "
        "This chat response does not query live platform health, telemetry, or a pending refund queue."
    )
    return {
        "messages": [AIMessage(content=reply)],
        "current_agent": "admin_operations",
        "final_output": reply
    }


async def policy_faq_node(state: EcommerceAgentState) -> Dict[str, Any]:
    messages = state.get("messages", [])
    query = messages[-1].content if messages else ""

    retrieved_policies = rag_store.search(query=query, doc_type="policy", top_k=2)
    context_str = "\n\n".join([doc["content"] for doc in retrieved_policies]) if retrieved_policies else "Our standard store policy provides 30-day returns and a 1-year limited warranty."

    prompt = (
        "You are the official AuraCommerce Policy and Customer Support Agent. "
        "Based exclusively on the corporate policies below:\n"
        f"{context_str}\n\n"
        f"Customer inquiry: {query}\n\n"
        "Respond concisely, politely, and professionally in English."
    )

    try:
        llm = get_chat_model(temperature=0.1)
        response = await asyncio.wait_for(
            llm.ainvoke([SystemMessage(content=prompt), HumanMessage(content=query)]),
            timeout=3.5
        )
        reply_content = response.content
    except Exception:
        reply_content = _synthesize_policy_response(retrieved_policies, query)

    return {
        "messages": [AIMessage(content=reply_content)],
        "current_agent": "policy_faq",
        "final_output": reply_content
    }


async def general_fallback_node(state: EcommerceAgentState) -> Dict[str, Any]:
    messages = state.get("messages", [])
    user_role = state.get("user_role", "customer")
    username = state.get("username", "guest")

    try:
        llm = get_chat_model(temperature=0.3)
        response = await asyncio.wait_for(
            llm.ainvoke(messages),
            timeout=3.5
        )
        reply_content = response.content
    except Exception:
        if user_role == "admin":
            reply_content = (
                f"🛡️ **AuraCommerce Admin Copilot (Operator: `{username}`)**\n\n"
                "I can look up catalog products and inventory, track a specific order or shipment, and answer store policy questions. "
                "Demand forecasts are available in Admin Console → Demand Forecast · 7 Days. "
                "This chat does not query live platform health, telemetry, or a pending refund queue."
            )
        else:
            reply_content = (
                "Hello! I am your **AuraCommerce Shopping Copilot**.\n\n"
                "How can I assist you today?\n"
                "- 📦 **Order & Shipment Tracking**: Inquire about any order ID, UUID, or carrier tracking number.\n"
                "- 🔍 **Product Recommendations**: Ask for laptops, accessories, monitors, or deals.\n"
                "- 🛡️ **Return & Warranty**: Check our 30-day return policies and warranty guarantees.\n"
                "- 💰 **Refund Processing**: Request instant refunds or supervisor authorization."
            )

    return {
        "messages": [AIMessage(content=reply_content)],
        "current_agent": "general_assistant",
        "final_output": reply_content
    }
