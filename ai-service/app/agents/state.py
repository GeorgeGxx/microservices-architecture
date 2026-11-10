from typing import List, Dict, Any, Optional, Annotated
from typing_extensions import TypedDict
from langchain_core.messages import BaseMessage
from langgraph.graph.message import add_messages


class EcommerceAgentState(TypedDict):
    """
    Unified state passed across all LangGraph nodes in the eCommerce workflow.
    """
    messages: Annotated[List[BaseMessage], add_messages]
    current_agent: str
    detected_intent: Optional[str]
    tool_calls: Optional[List[Dict[str, Any]]]
    hitl_pending: bool
    hitl_payload: Optional[Dict[str, Any]]
    final_output: Optional[str]
