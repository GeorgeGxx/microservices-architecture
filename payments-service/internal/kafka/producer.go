package kafka

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"time"

	"github.com/georgegxx/payments-service/internal/models"
	"github.com/segmentio/kafka-go"
)

type EventProducer interface {
	PublishPaymentCompleted(ctx context.Context, event models.PaymentCompletedEvent) error
	PublishPaymentFailed(ctx context.Context, event models.PaymentFailedEvent) error
	Close() error
}

type eventProducer struct {
	writer *kafka.Writer
	topic  string
}

func NewEventProducer(brokers []string, topic string) EventProducer {
	writer := &kafka.Writer{
		Addr:         kafka.TCP(brokers...),
		Topic:        topic,
		Balancer:     &kafka.LeastBytes{},
		BatchTimeout: 10 * time.Millisecond,
		Async:        false,
	}
	return &eventProducer{
		writer: writer,
		topic:  topic,
	}
}

func (p *eventProducer) PublishPaymentCompleted(ctx context.Context, event models.PaymentCompletedEvent) error {
	payload, err := json.Marshal(event)
	if err != nil {
		return fmt.Errorf("failed to marshal PaymentCompletedEvent: %w", err)
	}

	msg := kafka.Message{
		Key:   []byte(event.OrderNumber),
		Value: payload,
		Headers: []kafka.Header{
			{Key: "event_type", Value: []byte("PAYMENT_COMPLETED")},
		},
		Time: time.Now(),
	}

	if err := p.writer.WriteMessages(ctx, msg); err != nil {
		log.Printf("[Kafka Producer] Error publishing PaymentCompleted for order %s: %v", event.OrderNumber, err)
		return err
	}
	log.Printf("[Kafka Producer] Successfully published PaymentCompletedEvent for order %s (txn: %s)", event.OrderNumber, event.TransactionRef)
	return nil
}

func (p *eventProducer) PublishPaymentFailed(ctx context.Context, event models.PaymentFailedEvent) error {
	payload, err := json.Marshal(event)
	if err != nil {
		return fmt.Errorf("failed to marshal PaymentFailedEvent: %w", err)
	}

	msg := kafka.Message{
		Key:   []byte(event.OrderNumber),
		Value: payload,
		Headers: []kafka.Header{
			{Key: "event_type", Value: []byte("PAYMENT_FAILED")},
		},
		Time: time.Now(),
	}

	if err := p.writer.WriteMessages(ctx, msg); err != nil {
		log.Printf("[Kafka Producer] Error publishing PaymentFailed for order %s: %v", event.OrderNumber, err)
		return err
	}
	log.Printf("[Kafka Producer] Successfully published PaymentFailedEvent for order %s (reason: %s)", event.OrderNumber, event.Reason)
	return nil
}

func (p *eventProducer) Close() error {
	return p.writer.Close()
}
