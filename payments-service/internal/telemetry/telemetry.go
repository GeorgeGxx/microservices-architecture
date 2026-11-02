package telemetry

import (
	"context"
	"fmt"
	"log/slog"
	"os"
	"strings"

	"go.opentelemetry.io/otel"
	"go.opentelemetry.io/otel/exporters/otlp/otlptrace/otlptracehttp"
	"go.opentelemetry.io/otel/propagation"
	"go.opentelemetry.io/otel/sdk/resource"
	sdktrace "go.opentelemetry.io/otel/sdk/trace"
	semconv "go.opentelemetry.io/otel/semconv/v1.26.0"
	"go.opentelemetry.io/otel/trace"
)

// InitTracer initializes OpenTelemetry tracing and exports spans to Tempo/OTel collector.
func InitTracer(ctx context.Context, serviceName, environment string) (*sdktrace.TracerProvider, error) {
	endpoint := os.Getenv("OTEL_EXPORTER_OTLP_ENDPOINT")
	if endpoint == "" {
		endpoint = "http://localhost:4318"
	}
	endpoint = strings.TrimPrefix(endpoint, "http://")
	endpoint = strings.TrimPrefix(endpoint, "https://")

	exporter, err := otlptracehttp.New(ctx,
		otlptracehttp.WithEndpoint(endpoint),
		otlptracehttp.WithInsecure(),
		otlptracehttp.WithURLPath("/v1/traces"),
	)
	if err != nil {
		return nil, fmt.Errorf("failed to create OTLP trace exporter: %w", err)
	}

	res, err := resource.New(ctx,
		resource.WithAttributes(
			semconv.ServiceNameKey.String(serviceName),
			semconv.ServiceVersionKey.String("1.0.0"),
			semconv.DeploymentEnvironmentKey.String(environment),
		),
	)
	if err != nil {
		return nil, fmt.Errorf("failed to create telemetry resource: %w", err)
	}

	tp := sdktrace.NewTracerProvider(
		sdktrace.WithBatcher(exporter),
		sdktrace.WithResource(res),
		sdktrace.WithSampler(sdktrace.AlwaysSample()),
	)

	otel.SetTracerProvider(tp)
	otel.SetTextMapPropagator(propagation.NewCompositeTextMapPropagator(
		propagation.TraceContext{},
		propagation.Baggage{},
	))

	return tp, nil
}

// CorrelatedHandler is a custom slog handler formatting logs with [service,traceId,spanId]
type CorrelatedHandler struct {
	serviceName string
}

func NewCorrelatedLogger(serviceName string) *slog.Logger {
	return slog.New(&CorrelatedHandler{serviceName: serviceName})
}

func (h *CorrelatedHandler) Enabled(_ context.Context, _ slog.Level) bool {
	return true
}

func (h *CorrelatedHandler) Handle(ctx context.Context, r slog.Record) error {
	traceID := ""
	spanID := ""

	span := trace.SpanFromContext(ctx)
	if span != nil && span.SpanContext().IsValid() {
		traceID = span.SpanContext().TraceID().String()
		spanID = span.SpanContext().SpanID().String()
	}

	timeStr := r.Time.UTC().Format("2006-01-02T15:04:05.000Z07:00")
	levelStr := fmt.Sprintf("%5s", r.Level.String())

	attrs := ""
	r.Attrs(func(a slog.Attr) bool {
		attrs += fmt.Sprintf(" %s=%v", a.Key, a.Value.Any())
		return true
	})

	fmt.Fprintf(os.Stdout, "%s %s [%s,%s,%s] %s%s\n",
		timeStr,
		levelStr,
		h.serviceName,
		traceID,
		spanID,
		r.Message,
		attrs,
	)
	return nil
}

func (h *CorrelatedHandler) WithAttrs(_ []slog.Attr) slog.Handler {
	return h
}

func (h *CorrelatedHandler) WithGroup(_ string) slog.Handler {
	return h
}
