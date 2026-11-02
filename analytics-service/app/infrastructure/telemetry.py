import os
import logging
from opentelemetry import trace
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor
from opentelemetry.exporter.otlp.proto.http.trace_exporter import OTLPSpanExporter
from opentelemetry.sdk.resources import Resource
from opentelemetry.semconv.resource import ResourceAttributes
from opentelemetry.propagate import set_global_textmap
from opentelemetry.trace.propagation.tracecontext import TraceContextTextMapPropagator
from opentelemetry.instrumentation.fastapi import FastAPIInstrumentor
from opentelemetry.instrumentation.logging import LoggingInstrumentor

logger = logging.getLogger("Telemetry")

class CorrelatedLogFormatter(logging.Formatter):
    """Formats log records with ISO-8601 timestamp and [service,traceId,spanId] for Alloy/Loki correlation."""

    def format(self, record: logging.LogRecord) -> str:
        span = trace.get_current_span()
        span_ctx = span.get_span_context() if span else None

        if span_ctx and span_ctx.is_valid:
            trace_id = format(span_ctx.trace_id, "032x")
            span_id = format(span_ctx.span_id, "016x")
        else:
            trace_id = getattr(record, "otelTraceID", "") or ""
            span_id = getattr(record, "otelSpanID", "") or ""

        record.trace_correlation = f"[analytics-service,{trace_id},{span_id}]"
        return super().format(record)


def setup_telemetry(app, service_name: str = "analytics-service", environment: str = "dev"):
    """Configures OpenTelemetry distributed tracing and correlated logging."""
    otel_endpoint = os.getenv("OTEL_EXPORTER_OTLP_ENDPOINT", "http://localhost:4318")
    trace_url = otel_endpoint if otel_endpoint.endswith("/v1/traces") else f"{otel_endpoint.rstrip('/')}/v1/traces"

    resource = Resource.create({
        ResourceAttributes.SERVICE_NAME: service_name,
        ResourceAttributes.SERVICE_VERSION: "1.0.0",
        ResourceAttributes.DEPLOYMENT_ENVIRONMENT: environment,
    })

    provider = TracerProvider(resource=resource)
    try:
        exporter = OTLPSpanExporter(endpoint=trace_url)
        processor = BatchSpanProcessor(exporter)
        provider.add_span_processor(processor)
    except Exception as e:
        logger.warning(f"Could not connect to OTLP exporter at {trace_url}: {e}")

    trace.set_tracer_provider(provider)
    set_global_textmap(TraceContextTextMapPropagator())

    # Configure correlated logging
    LoggingInstrumentor().instrument(set_logging_format=False)
    handler = logging.StreamHandler()
    formatter = CorrelatedLogFormatter(
        "%(asctime)s %(levelname)5s %(trace_correlation)s [%(name)s] : %(message)s",
        datefmt="%Y-%m-%dT%H:%M:%S",
    )
    handler.setFormatter(formatter)
    
    root_logger = logging.getLogger()
    root_logger.handlers.clear()
    root_logger.addHandler(handler)
    root_logger.setLevel(logging.INFO)

    # Instrument FastAPI app
    FastAPIInstrumentor.instrument_app(app, tracer_provider=provider)
    logger.info(f"OpenTelemetry initialized for {service_name} -> {trace_url}")
    return provider
