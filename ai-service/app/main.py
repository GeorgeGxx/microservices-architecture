import asyncio
from contextlib import asynccontextmanager
from typing import List, Optional, Dict, Any
from fastapi import FastAPI, HTTPException, Depends
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import PlainTextResponse
from pydantic import BaseModel
from langchain_core.messages import HumanMessage

from app.config import settings
from app.rag.ingest import ingest_all
from app.observability.telemetry import setup_observability
from app.observability.evals import run_evaluations
from app.agents.graph import ecommerce_agent_app
from app.tools.mcp_server import EcommerceMCPServer, MCP_TOOLS_MANIFEST
from app.models.llm_factory import ensure_ollama_model_installed
from app.security import get_current_user, require_role


@asynccontextmanager
async def lifespan(app: FastAPI):
    print(f"[{settings.APP_NAME}] Starting AI Copilot Service on port {settings.PORT}...")
    ingest_all()
    setup_observability()
    if settings.LLM_PROVIDER == "ollama":
        asyncio.create_task(ensure_ollama_model_installed(settings.OLLAMA_BASE_URL, settings.OLLAMA_MODEL))
    yield
    print(f"[{settings.APP_NAME}] Shutting down.")


app = FastAPI(
    title=settings.APP_NAME,
    description="Enterprise AI Copilot Service for Microservices eCommerce Platform",
    version="1.0.0",
    lifespan=lifespan
)

# Enable CORS for the single React 19 Frontend (:5173) and local development
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Expose a minimal Prometheus-compatible metric until app instrumentation is configured.
@app.get("/metrics", response_class=PlainTextResponse, include_in_schema=False)
async def metrics():
    return "# HELP ai_service_up AI service process is running.\n# TYPE ai_service_up gauge\nai_service_up 1\n"


class ChatRequest(BaseModel):
    message: str
    thread_id: Optional[str] = "default-session"


class ChatResponse(BaseModel):
    reply: str
    active_agent: str
    intent: Optional[str]
    hitl_pending: bool
    hitl_payload: Optional[Dict[str, Any]] = None


class HITLApprovalRequest(BaseModel):
    ticket_id: str
    action: str
    supervisor_notes: Optional[str] = "Approved by store supervisor"


@app.get("/api/health")
async def health_check():
    return {
        "status": "healthy",
        "service": settings.APP_NAME,
        "port": settings.PORT,
        "layers": {
            "orchestration": "LangGraph StateGraph Active",
            "knowledge_rag": "ChromaDB / In-Memory Store Loaded",
            "models_llm": f"Provider: {settings.LLM_PROVIDER} ({settings.OLLAMA_MODEL})",
            "tools_mcp": f"Active ({len(MCP_TOOLS_MANIFEST)} tools registered)",
            "microservices_links": {
                "orders": settings.ORDERS_SERVICE_URL,
                "products": settings.PRODUCTS_SERVICE_URL,
                "inventory": settings.INVENTORY_SERVICE_URL,
                "cosmo_router": settings.COSMO_ROUTER_URL
            },
            "observability": f"Arize Phoenix ({settings.PHOENIX_COLLECTOR_ENDPOINT})" if settings.ENABLE_OBSERVABILITY else "Disabled"
        }
    }


@app.post("/api/chat", response_model=ChatResponse)
async def chat_endpoint(
    req: ChatRequest,
    current_user: Optional[Dict[str, Any]] = Depends(get_current_user)
):
    if not req.message.strip():
        raise HTTPException(status_code=400, detail="Message cannot be empty.")

    thread_config = {"configurable": {"thread_id": req.thread_id}}
    initial_state = {
        "messages": [HumanMessage(content=req.message)],
        "current_agent": "supervisor",
        "hitl_pending": False,
        "tool_calls": [],
        "hitl_payload": None,
        "final_output": None
    }

    try:
        final_state = await ecommerce_agent_app.ainvoke(initial_state, config=thread_config)
        return ChatResponse(
            reply=final_state.get("final_output", "Processed successfully."),
            active_agent=final_state.get("current_agent", "supervisor"),
            intent=final_state.get("detected_intent"),
            hitl_pending=final_state.get("hitl_pending", False),
            hitl_payload=final_state.get("hitl_payload")
        )
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Agent workflow error: {str(e)}")


@app.get("/api/tools")
async def get_mcp_tools():
    return {"tools": EcommerceMCPServer.list_tools()}


@app.post("/api/hitl/approve")
async def approve_hitl(
    req: HITLApprovalRequest,
    supervisor_user: Optional[Dict[str, Any]] = Depends(require_role("ROLE_SUPERVISOR"))
):
    status = "AUTHORIZED" if req.action.upper() == "APPROVE" else "DENIED"
    return {
        "success": True,
        "ticket_id": req.ticket_id,
        "status": status,
        "supervisor_notes": req.supervisor_notes,
        "message": f"Refund action was successfully {status.lower()} by supervisor."
    }


@app.post("/api/evals/run")
async def trigger_evals():
    summary = await run_evaluations()
    return summary


if __name__ == "__main__":
    import uvicorn
    uvicorn.run("app.main:app", host="0.0.0.0", port=settings.PORT, reload=True)
