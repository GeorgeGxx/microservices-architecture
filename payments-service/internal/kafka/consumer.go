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
}

type OrderEventConsumer struct {
	reader    *kafka.Reader
	processor PaymentProcessor
	stopChan  chan struct{}
}

func NewOrderEventConsumer(brokers []string, topic, groupID string, processor PaymentProcessor) *OrderEventConsumer {
	reader := kafka.NewReader(kafka.ReaderConfig{
		Brokers:        brokers,
		Topic:          topic,
		GroupID:        groupID,
		MinBytes:       10e3, // 10KB
		MaxBytes:       10e6, // 10MB
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
			go c.handleMessage(context.Background(), msg)
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

	// We only process orders awaiting payment: PENDING_PAYMENT or PLACED
	if !strings.EqualFold(orderStatus, "PENDING_PAYMENT") && !strings.EqualFold(orderStatus, "PLACED") {
		return
	}

	orderNumber, _ := rawEvent["orderNumber"].(string)
	if orderNumber == "" {
		orderNumber = string(msg.Key)
	}

	totalAmount, _ := rawEvent["totalAmount"].(float64)
	paymentMethod, _ := rawEvent["paymentMethod"].(string)
	if paymentMethod == "" {
		paymentMethod = "CARD_VISA"
	}
	customerEmail, _ := rawEvent["customerEmail"].(string)
	idempotencyKey, _ := rawEvent["idempotencyKey"].(string)
	if idempotencyKey == "" {
		idempotencyKey = "kafka-" + orderNumber
	}

	req := models.ProcessPaymentRequest{
		OrderNumber:    orderNumber,
		Amount:         totalAmount,
		Currency:       "USD",
		PaymentMethod:  paymentMethod,
		CustomerEmail:  customerEmail,
		IdempotencyKey: idempotencyKey,
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
