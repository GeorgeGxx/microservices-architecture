package metrics

import (
	"strconv"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/promauto"
)

var (
	PaymentsProcessedTotal = promauto.NewCounterVec(
		prometheus.CounterOpts{
			Name: "ecommerce_payments_total",
			Help: "Total number of payment transactions processed by payments-service",
		},
		[]string{"status", "payment_method"},
	)

	PaymentProcessingDuration = promauto.NewHistogramVec(
		prometheus.HistogramOpts{
			Name:    "ecommerce_payment_duration_seconds",
			Help:    "Duration of payment processing in seconds",
			Buckets: prometheus.DefBuckets,
		},
		[]string{"payment_method"},
	)

	PaymentRefundsTotal = promauto.NewCounterVec(
		prometheus.CounterOpts{
			Name: "ecommerce_payment_refunds_total",
			Help: "Total number of payment refunds processed",
		},
		[]string{"reason"},
	)

	AuditEventsDispatched = promauto.NewCounter(
		prometheus.CounterOpts{
			Name: "ecommerce_payment_audit_events_total",
			Help: "Total number of payment audit events processed asynchronously via goroutines",
		},
	)

	HttpServerRequests = promauto.NewHistogramVec(
		prometheus.HistogramOpts{
			Name:    "http_server_requests_seconds",
			Help:    "HTTP server request execution duration in seconds",
			Buckets: []float64{0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2.5, 5, 10},
		},
		[]string{"service", "status", "uri", "method"},
	)
)

// GinMetricsMiddleware records standardized RED metrics for incoming HTTP requests.
func GinMetricsMiddleware(serviceName string) gin.HandlerFunc {
	return func(c *gin.Context) {
		start := time.Now()
		c.Next()
		duration := time.Since(start).Seconds()

		status := strconv.Itoa(c.Writer.Status())
		path := c.FullPath()
		if path == "" {
			path = c.Request.URL.Path
		}

		HttpServerRequests.WithLabelValues(serviceName, status, path, c.Request.Method).Observe(duration)
	}
}
