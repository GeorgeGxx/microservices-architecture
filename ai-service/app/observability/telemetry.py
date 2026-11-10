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

        provider = TracerProvider()
        otlp_exporter = OTLPSpanExporter(endpoint=settings.PHOENIX_COLLECTOR_ENDPOINT)
        provider.add_span_processor(BatchSpanProcessor(otlp_exporter))
        trace.set_tracer_provider(provider)

        LangChainInstrumentor().instrument()
        logger.info("[Observability] OpenTelemetry tracing active -> Arize Phoenix at %s", settings.PHOENIX_COLLECTOR_ENDPOINT)
    except (ImportError, RuntimeError, ValueError) as exc:
        logger.debug("[Observability] Collector setup notice: %s", exc)
