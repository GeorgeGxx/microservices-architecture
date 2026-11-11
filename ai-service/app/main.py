import asyncio
import logging
import os
from contextlib import asynccontextmanager
from typing import Optional, Dict, Any, Set, Annotated
from fastapi import FastAPI, HTTPException, Depends
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import PlainTextResponse
from pydantic import BaseModel
from langchain_core.messages import HumanMessage

from app.config import settings
from app.rag.ingest import ingest_all
from app.observability.telemetry import setup_observability, emit_startup_trace, flush_telemetry
from app.observability.evals import run_evaluations
from app.agents.graph import ecommerce_agent_app
from app.tools.mcp_server import EcommerceMCPServer, MCP_TOOLS_MANIFEST
from app.models.llm_factory import ensure_ollama_model_installed
from app.security import get_current_user, require_role

logger = logging.getLogger("ai_service")
background_tasks: Set[asyncio.Task] = set()


@asynccontextmanager
async def lifespan(app: FastAPI):
    logger.info("[%s] Starting AI Copilot Service on port %s...", settings.APP_NAME, settings.PORT)
    ingest_all()
    setup_observability()
    emit_startup_trace()
    if settings.LLM_PROVIDER == "ollama":
        task = asyncio.create_task(ensure_ollama_model_installed(settings.OLLAMA_BASE_URL, settings.OLLAMA_MODEL))
        background_tasks.add(task)
        task.add_done_callback(background_tasks.discard)
    yield
    logger.info("[%s] Shutting down.", settings.APP_NAME)


app = FastAPI(
    title=settings.APP_NAME,
    description="Enterprise AI Copilot Service for Microservices eCommerce Platform",
    version="1.0.0",
    lifespan=lifespan
)

# Explicit allowed origins to satisfy security standards (prevents wildcard with credentials)
ALLOWED_ORIGINS = [
    "http://localhost:5173",
    "http://127.0.0.1:5173",
    "http://localhost:30088",
    "http://localhost:8080",
    "http://localhost:8010",
]

app.add_middleware(
    CORSMiddleware,
    allow_origins=ALLOWED_ORIGINS,
    allow_credentials=True,
    allow_methods=["GET", "POST", "PUT", "DELETE", "OPTIONS"],
    allow_headers=["Authorization", "Content-Type", "Accept"],
)

# Expose a minimal Prometheus-compatible metric until app instrumentation is configured.
@app.get("/metrics", response_class=PlainTextResponse, include_in_schema=False)
def metrics():
    return "# HELP ai_service_up AI service process is running.\n# TYPE ai_service_up gauge\nai_service_up 1\n"


class ChatRequest(BaseModel):
    message: str
    thread_id: Optional[str] = "default-session"
    user_role: Optional[str] = "customer"
    username: Optional[str] = "guest"


class ChatResponse(BaseModel):
    reply: str
    active_agent: str
    intent: Optional[str] = None
    hitl_pending: bool = False
    hitl_payload: Optional[Dict[str, Any]] = None


class HITLApprovalRequest(BaseModel):
    ticket_id: str
    action: str
    supervisor_notes: Optional[str] = "Approved by store supervisor"


@app.get("/health")
@app.get("/api/health")
def health_check():
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


@app.post(
    "/api/chat",
    response_model=ChatResponse,
    responses={
        400: {"description": "Bad Request - Empty message"},
        500: {"description": "Agent workflow error"}
    }
)
async def chat_endpoint(
    req: ChatRequest,
    current_user: Annotated[Optional[Dict[str, Any]], Depends(get_current_user)] = None
):
    if not req.message.strip():
        raise HTTPException(status_code=400, detail="Message cannot be empty.")

    user_role = req.user_role or "customer"
    username = req.username or "guest"
    if current_user and settings.SECURITY_ENABLED:
        roles = current_user.get("roles", [])
        if "ROLE_ADMIN" in roles or "admin" in roles:
            user_role = "admin"
        username = current_user.get("preferred_username", username)

    thread_config = {"configurable": {"thread_id": req.thread_id}}
    initial_state = {
        "messages": [HumanMessage(content=req.message)],
        "current_agent": "supervisor",
        "user_role": user_role,
        "username": username,
        "hitl_pending": False,
        "tool_calls": [],
        "hitl_payload": None,
        "final_output": None
    }

    try:
        final_state = await ecommerce_agent_app.ainvoke(initial_state, config=thread_config)
        flush_telemetry()
        return ChatResponse(
            reply=final_state.get("final_output", "Processed successfully."),
            active_agent=final_state.get("current_agent", "supervisor"),
            intent=final_state.get("detected_intent"),
            hitl_pending=final_state.get("hitl_pending", False),
            hitl_payload=final_state.get("hitl_payload")
        )
    except Exception as e:
        logger.exception("Agent workflow error: %s", e)
        raise HTTPException(status_code=500, detail=f"Agent workflow error: {str(e)}") from e


@app.get("/api/tools")
def get_mcp_tools():
    return {"tools": EcommerceMCPServer.list_tools()}


@app.post(
    "/api/hitl/approve",
    dependencies=[Depends(require_role("ROLE_SUPERVISOR"))]
)
def approve_hitl(req: HITLApprovalRequest):
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
    app_host = os.getenv("APP_HOST", "127.0.0.1")
    uvicorn.run("app.main:app", host=app_host, port=settings.PORT, reload=False)
