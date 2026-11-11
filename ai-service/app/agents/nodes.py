import re
from typing import Dict, Any, Optional
from langchain_core.messages import AIMessage, SystemMessage, HumanMessage

from app.agents.state import EcommerceAgentState
from app.models.llm_factory import get_chat_model
from app.rag.retriever import rag_store
from app.tools.mcp_server import EcommerceMCPServer
from app.config import settings


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
    elif any(k in last_user_msg for k in ["recommend", "laptop", "headphone", "mouse", "shoes", "precio", "catalogo", "catalog", "buy", "comprar", "suger"]):
        intent = "catalog"
    elif any(k in last_user_msg for k in ["policy", "politica", "garantia", "warranty", "shipping days", "dias de envio", "plazo"]):
        intent = "policy_faq"
    else:
        intent = "general"

    return {
        "current_agent": "supervisor",
        "detected_intent": intent
    }


async def product_advisor_node(state: EcommerceAgentState) -> Dict[str, Any]:
    messages = state.get("messages", [])
    query = messages[-1].content if messages else ""
    user_role = state.get("user_role", "customer")

    retrieved_items = rag_store.search(query=query, doc_type="product", top_k=2)
    context_str = "\n\n".join([doc["content"] for doc in retrieved_items]) if retrieved_items else "No specific catalog item matched."

    if user_role == "admin":
        prompt = (
            "You are the AuraCommerce Enterprise Operations Advisor assisting a store Administrator. "
            "Use the following catalog items:\n"
            f"{context_str}\n\n"
            f"Admin inquiry: {query}\n\n"
            "Provide an operational breakdown in English highlighting key specifications, retail price, "
            "estimated margin (~30%), safety stock requirements, and fulfillment guidance."
        )
    else:
        prompt = (
            "You are the AuraCommerce Product Specialist Advisor integrated with the products microservice. "
            "Use the following products retrieved from our knowledge base:\n"
            f"{context_str}\n\n"
            f"Customer inquiry: {query}\n\n"
            "Provide a clear, engaging recommendation highlighting key specifications, price, and customer benefits in English."
        )

    llm = get_chat_model(temperature=0.3)
    response = await llm.ainvoke([SystemMessage(content=prompt), HumanMessage(content=query)])

    return {
        "messages": [response],
        "current_agent": "product_advisor",
        "final_output": response.content
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
        if len(val) >= 4:
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
            f"\nDo you need additional assistance with this shipment or wish to initiate an exchange?"
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
            "Please provide your **Order ID** (e.g., `ORD-1001`) or **Carrier Tracking Number** "
            "(e.g., `DHL-88239104`) so I can check its current status."
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
            f"Please verify your Order ID (e.g., `ORD-1234`) or Carrier Tracking Number (e.g., `DHL-88239104`)."
        )

    return {
        "messages": [AIMessage(content=reply_text)],
        "current_agent": "order_support",
        "hitl_pending": False,
        "final_output": reply_text
    }


async def admin_ops_node(state: EcommerceAgentState) -> Dict[str, Any]:
    username = state.get("username", "admin")
    reply = (
        f"🛡️ **Admin Operations Portal (User: `{username}`)**:\n\n"
        f"• **Federated Supergraph**: Cosmo Router v2, Products, Orders, Inventory, Payments & Fulfillment active.\n"
        f"• **Demand Forecasting**: Integrated with MLflow & Prophet (`/api/forecast/preview`).\n"
        f"• **Observability**: OpenTelemetry distributed tracing active on Alloy & Tempo (`:3200`).\n"
        f"• **Supervisor HITL Gate**: StateGraph approval gates active for refunds > ${settings.REFUND_AUTO_APPROVE_LIMIT:.2f} USD.\n\n"
        f"Supervisor commands: Query inventory alerts, inspect order UUIDs, or review pending refund tickets."
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

    llm = get_chat_model(temperature=0.1)
    response = await llm.ainvoke([SystemMessage(content=prompt), HumanMessage(content=query)])

    return {
        "messages": [response],
        "current_agent": "policy_faq",
        "final_output": response.content
    }


async def general_fallback_node(state: EcommerceAgentState) -> Dict[str, Any]:
    messages = state.get("messages", [])
    llm = get_chat_model(temperature=0.3)
    response = await llm.ainvoke(messages)
    return {
        "messages": [response],
        "current_agent": "general_assistant",
        "final_output": response.content
    }
