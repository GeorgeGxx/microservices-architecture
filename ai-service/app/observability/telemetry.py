from app.config import settings


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
        print(f"[Observability] OpenTelemetry tracing active -> Arize Phoenix at {settings.PHOENIX_COLLECTOR_ENDPOINT}")
    except Exception as e:
        print(f"[Observability] Collector connection: {e}")
