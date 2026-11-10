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

func (c *OrderEventConsumer) parseEventPayload(msg kafka.Message) (*models.OrderEventPayload, string, error) {
	messageID := c.extractHeader(msg.Headers, "ce_id")
	if messageID == "" {
		messageID = c.extractHeader(msg.Headers, "idempotency-key")
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
		return &eventPayload, messageID, nil
	}

	if err := json.Unmarshal(msg.Value, &eventPayload); err != nil {
		return nil, "", err
	}
	return &eventPayload, messageID, nil
}

func isCompensationEvent(orderStatus, eventType string) bool {
	return strings.EqualFold(orderStatus, "CANCELLED") ||
		strings.EqualFold(orderStatus, "ORDER_CANCELLED") ||
		strings.EqualFold(eventType, "SHIPMENT_FAILED")
}

func isForwardPaymentEvent(orderStatus string) bool {
	return strings.EqualFold(orderStatus, "PENDING_PAYMENT") || strings.EqualFold(orderStatus, "PLACED")
}

func (c *OrderEventConsumer) recordProcessed(ctx context.Context, messageID, eventType string) {
	if c.repo == nil || messageID == "" {
		return
	}
	_ = c.repo.RecordProcessedMessage(ctx, &models.ProcessedMessage{
		MessageID:   messageID,
		ConsumerID:  "payments-service",
		EventType:   eventType,
		ProcessedAt: time.Now().UTC(),
	})
}

func (c *OrderEventConsumer) handleCompensatingRefund(ctx context.Context, msg kafka.Message, payload *models.OrderEventPayload, orderNumber, messageID string) error {
	reason := payload.Reason
	if reason == "" {
		reason = "Saga backward compensation (" + payload.ResolveStatus() + payload.ResolveEventType() + ")"
	}
	log.Printf("[Kafka Consumer] Executing Saga compensating refund for order %s (reason: %s)", orderNumber, reason)
	_, err := c.processor.RefundPayment(ctx, models.RefundPaymentRequest{
		OrderNumber: orderNumber,
		Reason:      reason,
	})
	if err != nil {
		log.Printf("[Kafka Consumer] Compensating refund skipped/failed for order %s: %v", orderNumber, err)
		return err
	}

	c.recordProcessed(ctx, messageID, payload.ResolveEventType())
	return c.reader.CommitMessages(ctx, msg)
}

func (c *OrderEventConsumer) handleForwardPayment(ctx context.Context, msg kafka.Message, payload *models.OrderEventPayload, orderNumber, messageID string) error {
	idempotencyKey := payload.IdempotencyKey
	if idempotencyKey == "" {
		idempotencyKey = "kafka-" + orderNumber
	}

	req := models.ProcessPaymentRequest{
		OrderNumber:     orderNumber,
		Amount:          payload.ResolveAmount(),
		Currency:        "USD",
		PaymentMethod:   payload.ResolvePaymentMethod(),
		CustomerEmail:   payload.CustomerEmail,
		CustomerName:    payload.CustomerName,
		ShippingAddress: payload.ShippingAddress,
		City:            payload.City,
		PostalCode:      payload.PostalCode,
		Phone:           payload.Phone,
		DeliveryMethod:  payload.DeliveryMethod,
		UserID:          payload.UserID,
		ItemsCount:      payload.ItemsCount,
		IdempotencyKey:  idempotencyKey,
	}

	log.Printf("[Kafka Consumer] Dispatched Saga payment processing for order %s ($%.2f via %s)", orderNumber, req.Amount, req.PaymentMethod)
	if _, err := c.processor.ProcessPayment(ctx, req); err != nil {
		log.Printf("[Kafka Consumer] Failed to process payment for order %s: %v", orderNumber, err)
		return err
	}

	c.recordProcessed(ctx, messageID, payload.ResolveEventType())
	return c.reader.CommitMessages(ctx, msg)
}

func (c *OrderEventConsumer) handleMessage(ctx context.Context, msg kafka.Message) error {
	headers := msg.Headers
	carrier := (*HeaderCarrier)(&headers)
	msgCtx := otel.GetTextMapPropagator().Extract(ctx, carrier)

	eventPayload, messageID, err := c.parseEventPayload(msg)
	if err != nil {
		log.Printf("[Kafka Consumer] Malformed JSON payload at offset %d: %v", msg.Offset, err)
		_ = c.reader.CommitMessages(msgCtx, msg)
		return nil
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

	if c.repo != nil && messageID != "" {
		if processed, err := c.repo.IsMessageProcessed(msgCtx, messageID); err == nil && processed {
			log.Printf("[Kafka Consumer] Message %s already processed; deduplicating", messageID)
			return c.reader.CommitMessages(msgCtx, msg)
		}
	}

	if isCompensationEvent(orderStatus, eventType) {
		return c.handleCompensatingRefund(msgCtx, msg, eventPayload, orderNumber, messageID)
	}

	if !isForwardPaymentEvent(orderStatus) {
		return c.reader.CommitMessages(msgCtx, msg)
	}

	return c.handleForwardPayment(msgCtx, msg, eventPayload, orderNumber, messageID)
}

func (c *OrderEventConsumer) Close() error {
	close(c.stopChan)
	return c.reader.Close()
}
