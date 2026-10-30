package kafka

import (
	"context"
	"encoding/json"
	"log"
	"strings"
	"time"

	"github.com/georgegxx/payments-service/internal/models"
	"github.com/segmentio/kafka-go"
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
	stopChan  chan struct{}
}

func NewOrderEventConsumer(brokers []string, topic, groupID string, processor PaymentProcessor) *OrderEventConsumer {
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

	return &OrderEventConsumer{
		reader:    reader,
		processor: processor,
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

			// Process message in dedicated goroutine
			go c.handleMessage(ctx, msg)
		}
	}
}

func (c *OrderEventConsumer) handleMessage(ctx context.Context, msg kafka.Message) {
	// Commit message offset once handled
	defer func() {
		if err := c.reader.CommitMessages(ctx, msg); err != nil {
			log.Printf("[Kafka Consumer] Failed to commit message at offset %d: %v", msg.Offset, err)
		}
	}()

	var rawEvent map[string]interface{}
	if err := json.Unmarshal(msg.Value, &rawEvent); err != nil {
		log.Printf("[Kafka Consumer] Malformed JSON payload at offset %d: %v", msg.Offset, err)
		return
	}

	orderStatus, _ := rawEvent["status"].(string)
	if orderStatus == "" {
		orderStatus, _ = rawEvent["orderStatus"].(string)
	}
	eventType, _ := rawEvent["eventType"].(string)
	if eventType == "" {
		eventType, _ = rawEvent["event_type"].(string)
	}

	orderNumber, _ := rawEvent["orderNumber"].(string)
	if orderNumber == "" {
		orderNumber, _ = rawEvent["order_number"].(string)
	}
	if orderNumber == "" {
		orderNumber = string(msg.Key)
	}

	// Backward Saga Compensation: Refund payment if order is CANCELLED or fulfillment SHIPMENT_FAILED
	if strings.EqualFold(orderStatus, "CANCELLED") ||
		strings.EqualFold(orderStatus, "ORDER_CANCELLED") ||
		strings.EqualFold(eventType, "SHIPMENT_FAILED") {
		reason, _ := rawEvent["reason"].(string)
		if reason == "" {
			reason = "Saga backward compensation (" + orderStatus + eventType + ")"
		}
		log.Printf("[Kafka Consumer] Executing Saga compensating refund for order %s (reason: %s)", orderNumber, reason)
		_, err := c.processor.RefundPayment(ctx, models.RefundPaymentRequest{
			OrderNumber: orderNumber,
			Reason:      reason,
		})
		if err != nil {
			log.Printf("[Kafka Consumer] Compensating refund skipped/failed for order %s: %v", orderNumber, err)
		}
		return
	}

	// Forward Saga Transition: Process orders awaiting payment (PENDING_PAYMENT or PLACED)
	if !strings.EqualFold(orderStatus, "PENDING_PAYMENT") && !strings.EqualFold(orderStatus, "PLACED") {
		return
	}

	totalAmount, _ := rawEvent["totalAmount"].(float64)
	paymentMethod, _ := rawEvent["paymentMethod"].(string)
	if paymentMethod == "" {
		paymentMethod = "CARD_VISA"
	}
	customerEmail, _ := rawEvent["customerEmail"].(string)
	customerName, _ := rawEvent["customerName"].(string)
	shippingAddress, _ := rawEvent["shippingAddress"].(string)
	city, _ := rawEvent["city"].(string)
	postalCode, _ := rawEvent["postalCode"].(string)
	phone, _ := rawEvent["phone"].(string)
	deliveryMethod, _ := rawEvent["deliveryMethod"].(string)
	userID, _ := rawEvent["userId"].(string)
	itemsCountFloat, _ := rawEvent["itemsCount"].(float64)
	idempotencyKey, _ := rawEvent["idempotencyKey"].(string)
	if idempotencyKey == "" {
		idempotencyKey = "kafka-" + orderNumber
	}

	req := models.ProcessPaymentRequest{
		OrderNumber:     orderNumber,
		Amount:          totalAmount,
		Currency:        "USD",
		PaymentMethod:   paymentMethod,
		CustomerEmail:   customerEmail,
		CustomerName:    customerName,
		ShippingAddress: shippingAddress,
		City:            city,
		PostalCode:      postalCode,
		Phone:           phone,
		DeliveryMethod:  deliveryMethod,
		UserID:          userID,
		ItemsCount:      int(itemsCountFloat),
		IdempotencyKey:  idempotencyKey,
	}

	log.Printf("[Kafka Consumer] Dispatched Saga payment processing for order %s ($%.2f via %s)", orderNumber, totalAmount, paymentMethod)
	_, err := c.processor.ProcessPayment(ctx, req)
	if err != nil {
		log.Printf("[Kafka Consumer] Failed to process payment for order %s: %v", orderNumber, err)
	}
}

func (c *OrderEventConsumer) Close() error {
	close(c.stopChan)
	return c.reader.Close()
}
