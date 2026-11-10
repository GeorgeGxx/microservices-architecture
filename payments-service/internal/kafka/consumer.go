package kafka

import (
	"context"
	"encoding/json"
	"log"
	"strings"
	"time"

	"github.com/georgegxx/payments-service/internal/models"
	"github.com/georgegxx/payments-service/internal/repository"
	"github.com/segmentio/kafka-go"
	"go.opentelemetry.io/otel"
)

type PaymentProcessor interface {
	ProcessPayment(ctx context.Context, req models.ProcessPaymentRequest) (*models.ProcessPaymentResponse, error)
	RefundPayment(ctx context.Context, req models.RefundPaymentRequest) (*models.Payment, error)
}

type messageReader interface {
	Config() kafka.ReaderConfig
	FetchMessage(ctx context.Context) (kafka.Message, error)
	CommitMessages(ctx context.Context, msgs ...kafka.Message) error
	Close() error
}

type OrderEventConsumer struct {
	reader    messageReader
	processor PaymentProcessor
	repo      repository.PaymentRepository
	stopChan  chan struct{}
}

func NewOrderEventConsumer(brokers []string, topic, groupID string, processor PaymentProcessor, repo ...repository.PaymentRepository) *OrderEventConsumer {
	reader := kafka.NewReader(kafka.ReaderConfig{
		Brokers:        brokers,
		Topic:          topic,
		GroupID:        groupID,
		MinBytes:       1,
		MaxBytes:       10e6, // 10MB
		MaxWait:        500 * time.Millisecond,
		CommitInterval: time.Second,
		StartOffset:    kafka.LastOffset,
	})

	var r repository.PaymentRepository
	if len(repo) > 0 {
		r = repo[0]
	}

	return &OrderEventConsumer{
		reader:    reader,
		processor: processor,
		repo:      r,
		stopChan:  make(chan struct{}),
	}
}

func (c *OrderEventConsumer) Start(ctx context.Context) {
	log.Printf("[Kafka Consumer] Listening for order events on topic: %s", c.reader.Config().Topic)

	for {
		select {
		case <-ctx.Done():
			log.Println("[Kafka Consumer] Context cancelled, stopping consumer...")
			return
		case <-c.stopChan:
			log.Println("[Kafka Consumer] Stop signal received, exiting loop...")
			return
		default:
			msg, err := c.reader.FetchMessage(ctx)
			if err != nil {
				if ctx.Err() != nil {
					return
				}
				log.Printf("[Kafka Consumer] Fetch error (retrying): %v", err)
				time.Sleep(500 * time.Millisecond)
				continue
			}

			// Process message synchronously to guarantee partition ordering & transactional commit safety
			if err := c.handleMessage(ctx, msg); err != nil {
				log.Printf("[Kafka Consumer] Failed to process message at offset %d: %v", msg.Offset, err)
			}
		}
	}
}

func (c *OrderEventConsumer) extractHeader(headers []kafka.Header, key string) string {
	for _, h := range headers {
		if strings.EqualFold(h.Key, key) {
			return string(h.Value)
		}
	}
	return ""
}

func (c *OrderEventConsumer) handleMessage(ctx context.Context, msg kafka.Message) error {
	headers := msg.Headers
	carrier := (*HeaderCarrier)(&headers)
	msgCtx := otel.GetTextMapPropagator().Extract(ctx, carrier)

	messageID := c.extractHeader(headers, "ce_id")
	if messageID == "" {
		messageID = c.extractHeader(headers, "idempotency-key")
	}

	var eventPayload models.OrderEventPayload
	var cloudEvent struct {
		ID   string          `json:"id"`
		Type string          `json:"type"`
		Data json.RawMessage `json:"data"`
	}

	if err := json.Unmarshal(msg.Value, &cloudEvent); err == nil && len(cloudEvent.Data) > 0 {
		if messageID == "" && cloudEvent.ID != "" {
			messageID = cloudEvent.ID
		}
		_ = json.Unmarshal(cloudEvent.Data, &eventPayload)
		if eventPayload.EventType == "" && cloudEvent.Type != "" {
			eventPayload.EventType = cloudEvent.Type
		}
	} else {
		if err := json.Unmarshal(msg.Value, &eventPayload); err != nil {
			log.Printf("[Kafka Consumer] Malformed JSON payload at offset %d: %v", msg.Offset, err)
			// Non-retryable poison pill; commit to avoid infinite processing loops
			_ = c.reader.CommitMessages(msgCtx, msg)
			return nil
		}
	}

	orderNumber := eventPayload.ResolveOrderNumber()
	if orderNumber == "" {
		orderNumber = string(msg.Key)
	}
	orderStatus := eventPayload.ResolveStatus()
	eventType := eventPayload.ResolveEventType()

	if messageID == "" {
		if eventPayload.IdempotencyKey != "" {
			messageID = eventPayload.IdempotencyKey
		} else if orderNumber != "" {
			messageID = orderNumber + ":" + orderStatus + ":" + eventType
		}
	}

	// Consumer Idempotency Check: prevent duplicate event processing
	if c.repo != nil && messageID != "" {
		processed, err := c.repo.IsMessageProcessed(msgCtx, messageID)
		if err == nil && processed {
			log.Printf("[Kafka Consumer] Message %s already processed; deduplicating", messageID)
			return c.reader.CommitMessages(msgCtx, msg)
		}
	}

	// Backward Saga Compensation: Refund payment if order is CANCELLED or fulfillment SHIPMENT_FAILED
	if strings.EqualFold(orderStatus, "CANCELLED") ||
		strings.EqualFold(orderStatus, "ORDER_CANCELLED") ||
		strings.EqualFold(eventType, "SHIPMENT_FAILED") {
		reason := eventPayload.Reason
		if reason == "" {
			reason = "Saga backward compensation (" + orderStatus + eventType + ")"
		}
		log.Printf("[Kafka Consumer] Executing Saga compensating refund for order %s (reason: %s)", orderNumber, reason)
		_, err := c.processor.RefundPayment(msgCtx, models.RefundPaymentRequest{
			OrderNumber: orderNumber,
			Reason:      reason,
		})
		if err != nil {
			log.Printf("[Kafka Consumer] Compensating refund skipped/failed for order %s: %v", orderNumber, err)
			return err
		}

		if c.repo != nil && messageID != "" {
			_ = c.repo.RecordProcessedMessage(msgCtx, &models.ProcessedMessage{
				MessageID:   messageID,
				ConsumerID:  "payments-service",
				EventType:   eventType,
				ProcessedAt: time.Now().UTC(),
			})
		}
		return c.reader.CommitMessages(msgCtx, msg)
	}

	// Forward Saga Transition: Process orders awaiting payment (PENDING_PAYMENT or PLACED)
	if !strings.EqualFold(orderStatus, "PENDING_PAYMENT") && !strings.EqualFold(orderStatus, "PLACED") {
		return c.reader.CommitMessages(msgCtx, msg)
	}

	totalAmount := eventPayload.ResolveAmount()
	paymentMethod := eventPayload.ResolvePaymentMethod()

	idempotencyKey := eventPayload.IdempotencyKey
	if idempotencyKey == "" {
		idempotencyKey = "kafka-" + orderNumber
	}

	req := models.ProcessPaymentRequest{
		OrderNumber:     orderNumber,
		Amount:          totalAmount,
		Currency:        "USD",
		PaymentMethod:   paymentMethod,
		CustomerEmail:   eventPayload.CustomerEmail,
		CustomerName:    eventPayload.CustomerName,
		ShippingAddress: eventPayload.ShippingAddress,
		City:            eventPayload.City,
		PostalCode:      eventPayload.PostalCode,
		Phone:           eventPayload.Phone,
		DeliveryMethod:  eventPayload.DeliveryMethod,
		UserID:          eventPayload.UserID,
		ItemsCount:      eventPayload.ItemsCount,
		IdempotencyKey:  idempotencyKey,
	}

	log.Printf("[Kafka Consumer] Dispatched Saga payment processing for order %s ($%.2f via %s)", orderNumber, totalAmount, paymentMethod)
	_, err := c.processor.ProcessPayment(msgCtx, req)
	if err != nil {
		log.Printf("[Kafka Consumer] Failed to process payment for order %s: %v", orderNumber, err)
		return err
	}

	if c.repo != nil && messageID != "" {
		_ = c.repo.RecordProcessedMessage(msgCtx, &models.ProcessedMessage{
			MessageID:   messageID,
			ConsumerID:  "payments-service",
			EventType:   eventType,
			ProcessedAt: time.Now().UTC(),
		})
	}

	return c.reader.CommitMessages(msgCtx, msg)
}

func (c *OrderEventConsumer) Close() error {
	close(c.stopChan)
	return c.reader.Close()
}
