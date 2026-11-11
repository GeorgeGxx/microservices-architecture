import logging
from app.config import settings

logger = logging.getLogger("observability_telemetry")


def setup_observability():
    if not settings.ENABLE_OBSERVABILITY:
        return

    try:
        from openinference.instrumentation.langchain import LangChainInstrumentor
        from opentelemetry import trace
        from opentelemetry.sdk.trace import TracerProvider
        from opentelemetry.sdk.trace.export import BatchSpanProcessor
        from opentelemetry.exporter.otlp.proto.http.trace_exporter import OTLPSpanExporter
        from opentelemetry.sdk.resources import Resource

        resource = Resource.create({
            "service.name": "ai-service",
            "project.name": "default",
            "openinference.project.name": "default"
        })
        provider = TracerProvider(resource=resource)
        otlp_exporter = OTLPSpanExporter(endpoint=settings.PHOENIX_COLLECTOR_ENDPOINT)
        provider.add_span_processor(BatchSpanProcessor(otlp_exporter, schedule_delay_millis=1000, max_export_batch_size=256))
        trace.set_tracer_provider(provider)

        LangChainInstrumentor().instrument()
        logger.info("[Observability] OpenTelemetry tracing active -> Arize Phoenix at %s", settings.PHOENIX_COLLECTOR_ENDPOINT)
    except (ImportError, RuntimeError, ValueError) as exc:
        logger.warning("[Observability] Collector setup notice: %s", exc)


def emit_startup_trace():
    """Emits an initial bootstrap trace so Arize Phoenix has instant visibility on startup."""
    if not settings.ENABLE_OBSERVABILITY:
        return
    try:
        from opentelemetry import trace
        tracer = trace.get_tracer("ai_service.bootstrap")
        with tracer.start_as_current_span(
            "ai_copilot_service_initialization",
            attributes={
                "openinference.span.kind": "chain",
                "service.name": "ai-service",
                "service.version": "1.0.0",
                "app.status": "healthy",
                "input.value": "AI Copilot Platform Bootstrap",
                "output.value": "AI Copilot Service Online with LangGraph, ChromaDB, and MCP Tools",
                "llm.provider": settings.LLM_PROVIDER,
                "project.name": "default",
            }
        ):
            logger.info("[Observability] Bootstrap warmup trace emitted to Arize Phoenix")
        flush_telemetry()
    except Exception as exc:
        logger.warning("[Observability] Failed to emit startup trace: %s", exc)


def flush_telemetry():
    try:
        from opentelemetry import trace
        provider = trace.get_tracer_provider()
        if hasattr(provider, "force_flush"):
            provider.force_flush(timeout_millis=3000)
    except Exception as exc:
        logger.debug("[Observability] Flush error: %s", exc)
