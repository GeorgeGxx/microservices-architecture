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


def flush_telemetry():
    try:
        from opentelemetry import trace
        provider = trace.get_tracer_provider()
        if hasattr(provider, "force_flush"):
            provider.force_flush(timeout_millis=3000)
    except Exception as exc:
        logger.debug("[Observability] Flush error: %s", exc)
