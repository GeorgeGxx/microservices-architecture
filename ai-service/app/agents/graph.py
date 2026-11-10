from langgraph.graph import StateGraph, END
from langgraph.checkpoint.memory import MemorySaver

from app.agents.state import EcommerceAgentState
from app.agents.nodes import (
    supervisor_router_node,
    product_advisor_node,
    order_support_node,
    policy_faq_node,
    general_fallback_node,
)


def route_decision(state: EcommerceAgentState) -> str:
    intent = state.get("detected_intent", "general")
    if intent == "catalog":
        return "product_advisor"
    elif intent == "order_support":
        return "order_support"
    elif intent == "policy_faq":
        return "policy_faq"
    return "general_fallback"


def create_ecommerce_graph():
    workflow = StateGraph(EcommerceAgentState)

    workflow.add_node("supervisor", supervisor_router_node)
    workflow.add_node("product_advisor", product_advisor_node)
    workflow.add_node("order_support", order_support_node)
    workflow.add_node("policy_faq", policy_faq_node)
    workflow.add_node("general_fallback", general_fallback_node)

    workflow.set_entry_point("supervisor")

    workflow.add_conditional_edges(
        "supervisor",
        route_decision,
        {
            "product_advisor": "product_advisor",
            "order_support": "order_support",
            "policy_faq": "policy_faq",
            "general_fallback": "general_fallback"
        }
    )

    workflow.add_edge("product_advisor", END)
    workflow.add_edge("order_support", END)
    workflow.add_edge("policy_faq", END)
    workflow.add_edge("general_fallback", END)

    checkpointer = MemorySaver()
    app = workflow.compile(checkpointer=checkpointer)
    return app


ecommerce_agent_app = create_ecommerce_graph()
