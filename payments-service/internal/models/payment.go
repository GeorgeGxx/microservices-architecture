package models

import (
	"time"

	"github.com/google/uuid"
)

type PaymentStatus string

const (
	PaymentStatusPending   PaymentStatus = "PENDING"
	PaymentStatusCompleted PaymentStatus = "COMPLETED"
	PaymentStatusFailed    PaymentStatus = "FAILED"
	PaymentStatusRefunded  PaymentStatus = "REFUNDED"
)

// Payment represents a financial transaction record in PostgreSQL 18
type Payment struct {
	ID             uuid.UUID     `gorm:"type:uuid;primaryKey" json:"id"`
	OrderNumber    string        `gorm:"type:varchar(64);index;not null" json:"order_number"`
	Amount         float64       `gorm:"type:decimal(12,2);not null" json:"amount"`
	Currency       string        `gorm:"type:varchar(3);default:'USD';not null" json:"currency"`
	Status         PaymentStatus `gorm:"type:varchar(20);index;not null" json:"status"`
	PaymentMethod  string        `gorm:"type:varchar(50);not null" json:"payment_method"`
	IdempotencyKey string        `gorm:"type:varchar(128);uniqueIndex" json:"idempotency_key"`
	TransactionRef string        `gorm:"type:varchar(100)" json:"transaction_ref"`
	FailureReason  string        `gorm:"type:text" json:"failure_reason,omitempty"`
	CustomerEmail  string        `gorm:"type:varchar(255)" json:"customer_email,omitempty"`
	CreatedAt      time.Time     `gorm:"not null" json:"created_at"`
	UpdatedAt      time.Time     `gorm:"not null" json:"updated_at"`
}

// PaymentAuditLog records asynchronous audit entries dispatched via goroutines
type PaymentAuditLog struct {
	ID        uuid.UUID `gorm:"type:uuid;primaryKey" json:"id"`
	PaymentID uuid.UUID `gorm:"type:uuid;index;not null" json:"payment_id"`
	Action    string    `gorm:"type:varchar(50);not null" json:"action"`
	Details   string    `gorm:"type:text" json:"details"`
	CreatedAt time.Time `gorm:"not null" json:"created_at"`
}

// Request and Response DTOs
type ProcessPaymentRequest struct {
	OrderNumber     string  `json:"order_number" binding:"required" example:"ORD-12345"`
	Amount          float64 `json:"amount" binding:"required,gt=0" example:"99.99"`
	Currency        string  `json:"currency" example:"USD"`
	PaymentMethod   string  `json:"payment_method" binding:"required" example:"CARD_VISA"`
	CustomerEmail   string  `json:"customer_email" example:"buyer@example.com"`
	IdempotencyKey  string  `json:"idempotency_key" example:"idem-uuid-99"`
	CustomerName    string  `json:"customer_name,omitempty"`
	ShippingAddress string  `json:"shipping_address,omitempty"`
	City            string  `json:"city,omitempty"`
	PostalCode      string  `json:"postal_code,omitempty"`
	Phone           string  `json:"phone,omitempty"`
	DeliveryMethod  string  `json:"delivery_method,omitempty"`
	UserID          string  `json:"user_id,omitempty"`
	ItemsCount      int     `json:"items_count,omitempty"`
}

type ProcessPaymentResponse struct {
	ID             uuid.UUID     `json:"id"`
	OrderNumber    string        `json:"order_number"`
	Amount         float64       `json:"amount"`
	Currency       string        `json:"currency"`
	Status         PaymentStatus `json:"status"`
	PaymentMethod  string        `json:"payment_method"`
	TransactionRef string        `json:"transaction_ref"`
	FailureReason  string        `json:"failure_reason,omitempty"`
	CreatedAt      time.Time     `json:"created_at"`
}

type RefundPaymentRequest struct {
	OrderNumber string  `json:"order_number" binding:"required" example:"ORD-12345"`
	Reason      string  `json:"reason" example:"Customer cancellation"`
	Amount      float64 `json:"amount" example:"99.99"`
}

type StandardResponse struct {
	Success bool        `json:"success" example:"true"`
	Message string      `json:"message" example:"Operation successful"`
	Data    interface{} `json:"data,omitempty"`
}

// Kafka Event Payloads
type OrderCreatedEvent struct {
	OrderNumber    string  `json:"order_number"`
	TotalAmount    float64 `json:"total_amount"`
	CustomerEmail  string  `json:"customer_email"`
	PaymentMethod  string  `json:"payment_method"`
	Status         string  `json:"status"`
	IdempotencyKey string  `json:"idempotency_key"`
}

type PaymentCompletedEvent struct {
	EventType       string    `json:"event_type"`
	Status          string    `json:"status"`
	PaymentID       string    `json:"payment_id"`
	OrderNumber     string    `json:"order_number"`
	Amount          float64   `json:"amount"`
	Currency        string    `json:"currency"`
	PaymentMethod   string    `json:"payment_method"`
	TransactionRef  string    `json:"transaction_ref"`
	CustomerName    string    `json:"customer_name,omitempty"`
	CustomerEmail   string    `json:"customer_email,omitempty"`
	ShippingAddress string    `json:"shipping_address,omitempty"`
	City            string    `json:"city,omitempty"`
	PostalCode      string    `json:"postal_code,omitempty"`
	Phone           string    `json:"phone,omitempty"`
	DeliveryMethod  string    `json:"delivery_method,omitempty"`
	UserID          string    `json:"user_id,omitempty"`
	ItemsCount      int       `json:"items_count,omitempty"`
	Timestamp       time.Time `json:"timestamp"`
}

type PaymentFailedEvent struct {
	EventType   string    `json:"event_type"`
	Status      string    `json:"status"`
	OrderNumber string    `json:"order_number"`
	Amount      float64   `json:"amount"`
	Reason      string    `json:"reason"`
	ErrorCode   string    `json:"error_code"`
	Timestamp   time.Time `json:"timestamp"`
}

type PaymentRefundedEvent struct {
	EventType   string    `json:"event_type"`
	Status      string    `json:"status"`
	OrderNumber string    `json:"order_number"`
	Amount      float64   `json:"amount"`
	Reason      string    `json:"reason"`
	Timestamp   time.Time `json:"timestamp"`
}

// ProcessedMessage provides exactly-once consumer idempotency deduplication
type ProcessedMessage struct {
	MessageID   string    `gorm:"type:varchar(128);primaryKey" json:"message_id"`
	ConsumerID  string    `gorm:"type:varchar(64);not null" json:"consumer_id"`
	EventType   string    `gorm:"type:varchar(64)" json:"event_type"`
	ProcessedAt time.Time `gorm:"not null" json:"processed_at"`
}

// OutboxEvent provides Transactional Outbox atomic Kafka dispatch
type OutboxEvent struct {
	ID            uuid.UUID  `gorm:"type:uuid;primaryKey" json:"id"`
	AggregateType string     `gorm:"type:varchar(64);not null" json:"aggregate_type"`
	AggregateID   string     `gorm:"type:varchar(128);not null" json:"aggregate_id"`
	EventType     string     `gorm:"type:varchar(64);not null" json:"event_type"`
	Payload       string     `gorm:"type:text;not null" json:"payload"`
	Status        string     `gorm:"type:varchar(20);default:'PENDING';not null;index" json:"status"`
	RetryCount    int        `gorm:"default:0" json:"retry_count"`
	CreatedAt     time.Time  `gorm:"not null;index" json:"created_at"`
	ProcessedAt   *time.Time `json:"processed_at,omitempty"`
}

// OrderEventPayload represents typed order events consumed by payments-service
type OrderEventPayload struct {
	OrderNumber     string  `json:"orderNumber"`
	AltOrderNumber  string  `json:"order_number"`
	OrderStatus     string  `json:"orderStatus"`
	AltOrderStatus  string  `json:"status"`
	EventType       string  `json:"eventType"`
	AltEventType    string  `json:"event_type"`
	TotalAmount     float64 `json:"totalAmount"`
	AltTotalAmount  float64 `json:"total_amount"`
	PaymentMethod   string  `json:"paymentMethod"`
	AltPaymentMethod string `json:"payment_method"`
	CustomerEmail   string  `json:"customerEmail"`
	CustomerName    string  `json:"customerName"`
	ShippingAddress string  `json:"shippingAddress"`
	City            string  `json:"city"`
	PostalCode      string  `json:"postalCode"`
	Phone           string  `json:"phone"`
	DeliveryMethod  string  `json:"deliveryMethod"`
	UserID          string  `json:"userId"`
	ItemsCount      int     `json:"itemsCount"`
	IdempotencyKey  string  `json:"idempotencyKey"`
	Reason          string  `json:"reason"`
}

func (p *OrderEventPayload) ResolveOrderNumber() string {
	if p.OrderNumber != "" {
		return p.OrderNumber
	}
	return p.AltOrderNumber
}

func (p *OrderEventPayload) ResolveStatus() string {
	if p.OrderStatus != "" {
		return p.OrderStatus
	}
	return p.AltOrderStatus
}

func (p *OrderEventPayload) ResolveEventType() string {
	if p.EventType != "" {
		return p.EventType
	}
	return p.AltEventType
}

func (p *OrderEventPayload) ResolveAmount() float64 {
	if p.TotalAmount > 0 {
		return p.TotalAmount
	}
	return p.AltTotalAmount
}

func (p *OrderEventPayload) ResolvePaymentMethod() string {
	if p.PaymentMethod != "" {
		return p.PaymentMethod
	}
	if p.AltPaymentMethod != "" {
		return p.AltPaymentMethod
	}
	return "CARD_VISA"
}

