package kafka

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"strings"
	"time"

	"github.com/georgegxx/payments-service/internal/models"
	"github.com/google/uuid"
	"github.com/segmentio/kafka-go"
	"go.opentelemetry.io/otel"
)

type EventProducer interface {
	PublishPaymentCompleted(ctx context.Context, event models.PaymentCompletedEvent) error
	PublishPaymentFailed(ctx context.Context, event models.PaymentFailedEvent) error
	PublishPaymentRefunded(ctx context.Context, event models.PaymentRefundedEvent) error
	Close() error
}

type messageWriter interface {
	WriteMessages(ctx context.Context, msgs ...kafka.Message) error
	Close() error
}

type eventProducer struct {
	writer messageWriter
	topic  string
}

func NewEventProducer(brokers []string, topic string) EventProducer {
	writer := &kafka.Writer{
		Addr:                   kafka.TCP(brokers...),
		Topic:                  topic,
		Balancer:               &kafka.LeastBytes{},
		BatchTimeout:           10 * time.Millisecond,
		Async:                  false,
		AllowAutoTopicCreation: true,
	}
	return &eventProducer{
		writer: writer,
		topic:  topic,
	}
}

func (p *eventProducer) publishEvent(ctx context.Context, orderNumber, eventType string, event interface{}, logDetail string) error {
	eventId := uuid.New().String()
	cloudEventType := "com.georgegxx.payments." + strings.ToLower(strings.ReplaceAll(eventType, "_", "-"))
	currentTime := time.Now().UTC().Format(time.RFC3339)

	// Build CloudEvents 1.0 envelope with root backward-compatibility fields
	cloudEventMap := map[string]interface{}{
		"specversion":     "1.0",
		"id":              eventId,
		"source":          "/payments-service",
		"type":            cloudEventType,
		"time":            currentTime,
		"datacontenttype": "application/json",
		"data":            event,
	}

	eventBytes, err := json.Marshal(event)
	if err != nil {
		return fmt.Errorf("failed to marshal %s: %w", eventType, err)
	}

	var flatMap map[string]interface{}
	if err := json.Unmarshal(eventBytes, &flatMap); err == nil {
		for k, v := range flatMap {
			cloudEventMap[k] = v
		}
	}

	payload, err := json.Marshal(cloudEventMap)
	if err != nil {
		return fmt.Errorf("failed to marshal CloudEvent %s: %w", eventType, err)
	}

	headers := []kafka.Header{
		{Key: "event_type", Value: []byte(eventType)},
		{Key: "ce_specversion", Value: []byte("1.0")},
		{Key: "ce_type", Value: []byte(cloudEventType)},
		{Key: "ce_source", Value: []byte("/payments-service")},
		{Key: "ce_id", Value: []byte(eventId)},
	}
	carrier := (*HeaderCarrier)(&headers)
	otel.GetTextMapPropagator().Inject(ctx, carrier)

	msg := kafka.Message{
		Key:     []byte(orderNumber),
		Value:   payload,
		Headers: headers,
		Time:    time.Now(),
	}

	if err := p.writer.WriteMessages(ctx, msg); err != nil {
		log.Printf("[Kafka Producer] Error publishing %s for order %s: %v", eventType, orderNumber, err)
		return err
	}
	log.Printf("[Kafka Producer] Successfully published %s for order %s (%s)", eventType, orderNumber, logDetail)
	return nil
}

func (p *eventProducer) PublishPaymentCompleted(ctx context.Context, event models.PaymentCompletedEvent) error {
	return p.publishEvent(ctx, event.OrderNumber, "PAYMENT_COMPLETED", event, "txn: "+event.TransactionRef)
}

func (p *eventProducer) PublishPaymentFailed(ctx context.Context, event models.PaymentFailedEvent) error {
	return p.publishEvent(ctx, event.OrderNumber, "PAYMENT_FAILED", event, "reason: "+event.Reason)
}

func (p *eventProducer) PublishPaymentRefunded(ctx context.Context, event models.PaymentRefundedEvent) error {
	return p.publishEvent(ctx, event.OrderNumber, "PAYMENT_REFUNDED", event, "reason: "+event.Reason)
}

func (p *eventProducer) Close() error {
	return p.writer.Close()
}
