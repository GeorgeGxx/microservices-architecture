package telemetry

import (
	"context"
	"io"
	"log/slog"
	"os"
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
	"go.opentelemetry.io/otel"
	sdktrace "go.opentelemetry.io/otel/sdk/trace"
	"go.opentelemetry.io/otel/trace"
)

func TestInitTracer(t *testing.T) {
	ctx := context.Background()
	tp, err := InitTracer(ctx, "payments-service-test", "test")
	assert.NoError(t, err)
	assert.NotNil(t, tp)

	tracer := otel.Tracer("test-tracer")
	ctx, span := tracer.Start(ctx, "test-span")
	assert.True(t, span.SpanContext().IsValid())
	span.End()

	logger := NewCorrelatedLogger("payments-service-test")
	assert.NotNil(t, logger)
	logger.InfoContext(ctx, "Test log message with active trace correlation")

	_ = tp.Shutdown(ctx)
}

func TestCorrelatedHandlerWithoutSpan(t *testing.T) {
	ctx := context.Background()
	logger := NewCorrelatedLogger("payments-service-test")
	assert.NotNil(t, logger)
	logger.InfoContext(ctx, "Test log message without span")
}

func TestInitGlitchTipWithoutDSN(t *testing.T) {
	t.Setenv("SENTRY_DSN", "")
	InitGlitchTip("payments-service-test", "test")
	FlushGlitchTip()
}

func TestCorrelatedHandlerWritesTraceAndAttributes(t *testing.T) {
	read, write, err := os.Pipe()
	assert.NoError(t, err)
	defer read.Close()
	previousStdout := os.Stdout
	os.Stdout = write
	t.Cleanup(func() { os.Stdout = previousStdout })

	handler := &CorrelatedHandler{serviceName: "payments-service-test"}
	spanContext := trace.NewSpanContext(trace.SpanContextConfig{
		TraceID: trace.TraceID{1}, SpanID: trace.SpanID{1}, TraceFlags: trace.FlagsSampled,
	})
	ctx := trace.ContextWithSpanContext(context.Background(), spanContext)
	record := slog.NewRecord(time.Date(2026, 1, 2, 3, 4, 5, 0, time.UTC), slog.LevelInfo, "payment accepted", 0)
	record.AddAttrs(slog.String("order", "ORD-1"))
	assert.NoError(t, handler.Handle(ctx, record))

	assert.NoError(t, write.Close())
	output, err := io.ReadAll(read)
	assert.NoError(t, err)
	assert.Contains(t, string(output), "payments-service-test")
	assert.Contains(t, string(output), "payment accepted")
	assert.Contains(t, string(output), "order=ORD-1")
	assert.Contains(t, string(output), spanContext.TraceID().String())
}

func TestCorrelatedHandlerWithAttrsAndGroupPreservesHandler(t *testing.T) {
	handler := &CorrelatedHandler{serviceName: "payments-service-test"}
	assert.Same(t, handler, handler.WithAttrs([]slog.Attr{slog.String("key", "value")}))
	assert.Same(t, handler, handler.WithGroup("request"))
	assert.True(t, handler.Enabled(context.Background(), slog.LevelDebug))
}

func init() {
	// Ensure tests do not fail if tracer provider is already registered
	_ = sdktrace.AlwaysSample()
}
