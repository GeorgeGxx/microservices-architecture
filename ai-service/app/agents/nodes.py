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

    if any(k in last_user_msg for k in ["order", "ord-", "tracking", "track", "shipment", "carrier", "refund", "devoluc", "reembolso", "paquete", "dhl"]):
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

    retrieved_items = rag_store.search(query=query, doc_type="product", top_k=2)
    context_str = "\n\n".join([doc["content"] for doc in retrieved_items]) if retrieved_items else "No specific catalog item matched."

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
    # 1. Standard Order ID (e.g. ORD-1001)
    ord_match = re.search(r"\bORD-(\d+)\b", user_msg, re.IGNORECASE)
    if ord_match:
        return f"ORD-{ord_match.group(1)}"

    # 2. Carrier tracking numbers (e.g. DHL-88239104, FDX-D1D28072, UPS-12345)
    carrier_match = re.search(r"\b([A-Za-z]{2,5}-[A-Za-z0-9]+)\b", user_msg)
    if carrier_match:
        return carrier_match.group(1).upper()

    # 3. Explicit tracking keywords (e.g. tracking FDX-D1D28072, guia DHL8823)
    keyword_match = re.search(
        r"(?:tracking|guia|guía|rastreo|shipment)\s*(?:number|code|id|no\.?|#)?\s*[:#]?\s*([A-Za-z0-9\-]+)",
        user_msg,
        re.IGNORECASE
    )
    if keyword_match:
        val = keyword_match.group(1).strip("-").upper()
        if len(val) >= 4:
            return val

    # 4. Numeric order patterns (e.g. order #1001, pedido 1002)
    order_num_match = re.search(r"(?:order|pedido)\s*(?:number|id|no\.?|#)?\s*[:#]?\s*(\d{1,8})\b", user_msg, re.IGNORECASE)
    if order_num_match:
        return f"ORD-{order_num_match.group(1)}"

    return None


async def order_support_node(state: EcommerceAgentState) -> Dict[str, Any]:
    messages = state.get("messages", [])
    user_msg = messages[-1].content if messages else ""

    order_id = _extract_order_or_tracking_id(user_msg)
    is_refund = any(w in user_msg.lower() for w in ["refund", "reembolso", "devolver", "return", "cancel"])

    if is_refund:
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

        if not order_id.startswith("ORD-"):
            lookup = await EcommerceMCPServer.call_tool("get_order_details", {"order_id": order_id})
            if lookup.get("success") and "data" in lookup and "order_id" in lookup["data"]:
                order_id = lookup["data"]["order_id"]

        amount_match = re.search(r"\$\s*(\d+(?:\.\d{1,2})?)", user_msg)
        if not amount_match:
            amount_match = re.search(r"\b(\d+(?:\.\d{1,2})?)\s*(?:usd|dollars|dolares)\b", user_msg, re.IGNORECASE)
        amount = float(amount_match.group(1)) if amount_match else 75.00

        tool_result = await EcommerceMCPServer.call_tool("request_refund", {
            "order_id": order_id,
            "amount": amount,
            "reason": user_msg
        })

        if amount > settings.REFUND_AUTO_APPROVE_LIMIT:
            reply_text = (
                f"We have registered your refund request for order **{order_id}** in the amount of **${amount:.2f} USD**.\n\n"
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
        else:
            reply_text = (
                f"Your refund request for order **{order_id}** for **${amount:.2f} USD** was **automatically approved**.\n"
                f"Ticket reference: `{tool_result['data']['refund_ticket']}`. The credit will reflect on your original payment method in 3 to 5 business days."
            )
            return {
                "messages": [AIMessage(content=reply_text)],
                "current_agent": "order_support",
                "hitl_pending": False,
                "final_output": reply_text
            }

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
        data = tool_result["data"]
        items_summary = ", ".join([f"{it['name']} (x{it['qty']})" for it in data.get("items", [])]) if data.get("items") else "Standard catalog items"
        carrier_label = data.get("carrier", "Carrier")
        reply_text = (
            f"📦 **Order Status for {data['order_id']}**:\n"
            f"- **Status:** {data['status']}\n"
            f"- **Carrier:** {carrier_label}\n"
            f"- **Tracking Number:** `{data['tracking_number']}`\n"
            f"- **Items:** {items_summary}\n"
            f"- **Total:** ${data.get('total', 0.0):.2f} USD\n\n"
            f"Do you need additional assistance with this shipment or wish to initiate an exchange?"
        )
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
