import json
import re
from typing import Dict, Any
from langchain_core.messages import AIMessage, SystemMessage, HumanMessage

from app.agents.state import EcommerceAgentState
from app.models.llm_factory import get_chat_model
from app.rag.retriever import rag_store
from app.tools.mcp_server import EcommerceMCPServer
from app.config import settings


async def supervisor_router_node(state: EcommerceAgentState) -> Dict[str, Any]:
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


async def order_support_node(state: EcommerceAgentState) -> Dict[str, Any]:
    messages = state.get("messages", [])
    user_msg = messages[-1].content

    order_match = re.search(r"ORD-\d+", user_msg, re.IGNORECASE)
    order_id = order_match.group(0).upper() if order_match else "ORD-1001"

    is_refund = any(w in user_msg.lower() for w in ["refund", "reembolso", "devolver", "return", "cancel"])

    if is_refund:
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
    tool_result = await EcommerceMCPServer.call_tool("get_order_details", {"order_id": order_id})
    if tool_result.get("success"):
        data = tool_result["data"]
        items_summary = ", ".join([f"{it['name']} (x{it['qty']})" for it in data.get("items", [])]) if data.get("items") else "Standard catalog items"
        reply_text = (
            f"📦 **Order Status for {data['order_id']}**:\n"
            f"- **Status:** {data['status']}\n"
            f"- **Carrier:** {data['carrier']}\n"
            f"- **DHL Tracking Number:** `{data['tracking_number']}`\n"
            f"- **Items:** {items_summary}\n"
            f"- **Total:** ${data.get('total', 0.0):.2f} USD\n\n"
            f"Do you need additional assistance with this shipment or wish to initiate an exchange?"
        )
    else:
        reply_text = f"We could not find order `{order_id}` in our microservices database. Please verify your order number (e.g., ORD-1001, ORD-1002)."

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
