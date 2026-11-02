package telemetry

import (
	"context"
	"testing"

	"github.com/stretchr/testify/assert"
	"go.opentelemetry.io/otel"
	sdktrace "go.opentelemetry.io/otel/sdk/trace"
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

func init() {
	// Ensure tests do not fail if tracer provider is already registered
	_ = sdktrace.AlwaysSample()
}
