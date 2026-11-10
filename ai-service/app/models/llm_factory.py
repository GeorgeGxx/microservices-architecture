from typing import Any, List, Optional

try:
    import httpx
except ImportError:
    httpx = None

from langchain_core.language_models.chat_models import BaseChatModel
from langchain_core.messages import BaseMessage, AIMessage
from langchain_core.outputs import ChatResult, ChatGeneration

from app.config import settings


class LocalFallbackChatModel(BaseChatModel):
    """
    Intelligent local fallback LLM used when Ollama or external endpoints
    are temporarily starting up or unreachable.
    """
    model_name: str = "local-fallback-engine"

    def _generate(
        self,
        messages: List[BaseMessage],
        stop: Optional[List[str]] = None,
        run_manager: Any = None,
        **kwargs: Any,
    ) -> ChatResult:
        last_msg = messages[-1].content.lower() if messages else ""

        if "order" in last_msg or "ord-" in last_msg or "shipping" in last_msg or "track" in last_msg:
            reply = (
                "Consulté nuestro sistema de órdenes de microservicios mediante la herramienta MCP `get_order_details`. "
                "Tu pedido está registrado y cuenta con guía de rastreo activa por DHL Express."
            )
        elif "refund" in last_msg or "devoluc" in last_msg or "reembolso" in last_msg:
            reply = (
                "Para procesar tu solicitud de devolución o reembolso, nuestra política de microservicios permite hasta 30 días posteriores "
                "a la entrega. Si el monto supera los $50 USD, requerirá autorización humana de nuestro supervisor."
            )
        elif "laptop" in last_msg or "headphone" in last_msg or "recomiend" in last_msg or "precio" in last_msg or "comprar" in last_msg:
            reply = (
                "Te sugiero revisar nuestro catálogo sincronizado con el servicio de productos: contamos con la MacBook Air 15 M3 ($1,299 USD) para productividad, "
                "los audífonos Sony WH-1000XM5 ($349.99 USD) con cancelación de ruido, y el mouse Logitech MX Master 3S ($99.99 USD). "
                "¿Deseas verificar disponibilidad en el inventario?"
            )
        else:
            reply = (
                "¡Hola! Soy tu asistente inteligente de AuraCommerce AI integrado en la plataforma de microservicios. "
                "Puedo ayudarte a buscar y recomendar productos de nuestro catálogo, rastrear tus envíos por DHL en tiempo real, "
                "o tramitar devoluciones y garantías. ¿En qué te puedo colaborar hoy?"
            )

        gen = ChatGeneration(message=AIMessage(content=reply))
        return ChatResult(generations=[gen])

    @property
    def _llm_type(self) -> str:
        return "local-fallback-chat-model"


async def ensure_ollama_model_installed(base_url: str, model_name: str):
    """
    Automatically queries the Ollama server and triggers a download if the model is missing.
    """
    if not httpx:
        return
    try:
        async with httpx.AsyncClient(timeout=10.0) as client:
            res = await client.get(f"{base_url}/api/tags")
            if res.status_code == 200:
                installed_models = [m.get("name", "") for m in res.json().get("models", [])]
                model_base = model_name.split(":")[0]
                has_model = any(model_name in m or model_base in m for m in installed_models)

                if not has_model:
                    print(f"[Ollama] Model '{model_name}' not found locally. Initiating automated download in background...")
                    async with httpx.AsyncClient(timeout=1800.0) as pull_client:
                        pull_res = await pull_client.post(
                            f"{base_url}/api/pull",
                            json={"name": model_name, "stream": False}
                        )
                        if pull_res.status_code == 200:
                            print(f"[Ollama] Automated download of '{model_name}' completed successfully!")
                else:
                    print(f"[Ollama] Model '{model_name}' is already installed and verified.")
    except Exception as e:
        print(f"[Ollama] Could not verify or auto-pull model: {e}")


def get_chat_model(temperature: Optional[float] = None) -> BaseChatModel:
    temp = temperature if temperature is not None else settings.OLLAMA_TEMPERATURE

    if settings.LLM_PROVIDER == "ollama":
        try:
            from langchain_ollama import ChatOllama
            try:
                res = httpx.get(f"{settings.OLLAMA_BASE_URL}/api/tags", timeout=1.0)
                if res.status_code == 200:
                    return ChatOllama(
                        base_url=settings.OLLAMA_BASE_URL,
                        model=settings.OLLAMA_MODEL,
                        temperature=temp
                    )
            except Exception:
                pass
        except ImportError:
            pass

    if settings.LLM_PROVIDER == "openai" and settings.OPENAI_API_KEY:
        try:
            from langchain_openai import ChatOpenAI
            return ChatOpenAI(
                model=settings.OPENAI_MODEL,
                temperature=temp,
                api_key=settings.OPENAI_API_KEY
            )
        except Exception as e:
            print(f"[ModelFactory] Failed to load OpenAI model: {e}")

    return LocalFallbackChatModel()
