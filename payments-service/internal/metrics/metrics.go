package metrics

import (
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
)
