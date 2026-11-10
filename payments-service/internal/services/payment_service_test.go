package services_test

import (
	"context"
	"encoding/json"
	"sync"
	"testing"

	"github.com/georgegxx/payments-service/internal/models"
	"github.com/georgegxx/payments-service/internal/services"
	"github.com/google/uuid"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/mock"
)

// MockPaymentRepository is an in-memory mock implementation
type MockPaymentRepository struct {
	mock.Mock
	payments     map[string]*models.Payment
	outboxEvents map[string]*models.OutboxEvent
	mu           sync.RWMutex
}

func NewMockPaymentRepository() *MockPaymentRepository {
	return &MockPaymentRepository{
		payments:     make(map[string]*models.Payment),
		outboxEvents: make(map[string]*models.OutboxEvent),
	}
}

func (m *MockPaymentRepository) CreatePayment(ctx context.Context, p *models.Payment) error {
	m.mu.Lock()
	defer m.mu.Unlock()
	m.payments[p.OrderNumber] = p
	if p.IdempotencyKey != "" {
		m.payments["idem:"+p.IdempotencyKey] = p
	}
	m.payments["id:"+p.ID.String()] = p
	return nil
}

func (m *MockPaymentRepository) UpdatePayment(ctx context.Context, p *models.Payment) error {
	m.mu.Lock()
	defer m.mu.Unlock()
	m.payments[p.OrderNumber] = p
	return nil
}

func (m *MockPaymentRepository) FindByID(ctx context.Context, id uuid.UUID) (*models.Payment, error) {
	m.mu.RLock()
	defer m.mu.RUnlock()
	if p, ok := m.payments["id:"+id.String()]; ok {
		return p, nil
	}
	return nil, nil
}

func (m *MockPaymentRepository) FindByOrderNumber(ctx context.Context, orderNumber string) (*models.Payment, error) {
	m.mu.RLock()
	defer m.mu.RUnlock()
	if p, ok := m.payments[orderNumber]; ok {
		return p, nil
	}
	return nil, nil
}

func (m *MockPaymentRepository) FindByIdempotencyKey(ctx context.Context, key string) (*models.Payment, error) {
	m.mu.RLock()
	defer m.mu.RUnlock()
	if p, ok := m.payments["idem:"+key]; ok {
		return p, nil
	}
	return nil, nil
}

func (m *MockPaymentRepository) CreateAuditLog(ctx context.Context, log *models.PaymentAuditLog) error {
	return nil
}

func (m *MockPaymentRepository) IsMessageProcessed(ctx context.Context, messageID string) (bool, error) {
	return false, nil
}

func (m *MockPaymentRepository) RecordProcessedMessage(ctx context.Context, msg *models.ProcessedMessage) error {
	return nil
}

func (m *MockPaymentRepository) SaveOutboxEvent(ctx context.Context, event *models.OutboxEvent) error {
	m.mu.Lock()
	defer m.mu.Unlock()
	m.outboxEvents[event.ID.String()] = event
	return nil
}

func (m *MockPaymentRepository) GetPendingOutboxEvents(ctx context.Context, limit int) ([]models.OutboxEvent, error) {
	m.mu.RLock()
	defer m.mu.RUnlock()
	var pending []models.OutboxEvent
	for _, ev := range m.outboxEvents {
		if ev.Status == "PENDING" {
			pending = append(pending, *ev)
			if limit > 0 && len(pending) >= limit {
				break
			}
		}
	}
	return pending, nil
}

func (m *MockPaymentRepository) UpdateOutboxEvent(ctx context.Context, event *models.OutboxEvent) error {
	m.mu.Lock()
	defer m.mu.Unlock()
	m.outboxEvents[event.ID.String()] = event
	return nil
}

// MockProducer
type MockEventProducer struct {
	mock.Mock
}

func (m *MockEventProducer) PublishPaymentCompleted(ctx context.Context, event models.PaymentCompletedEvent) error {
	m.Called(ctx, event)
	return nil
}

func (m *MockEventProducer) PublishPaymentFailed(ctx context.Context, event models.PaymentFailedEvent) error {
	m.Called(ctx, event)
	return nil
}

func (m *MockEventProducer) PublishPaymentRefunded(ctx context.Context, event models.PaymentRefundedEvent) error {
	m.Called(ctx, event)
	return nil
}

func (m *MockEventProducer) Close() error {
	return nil
}

func TestProcessPayment_Success(t *testing.T) {
	repo := NewMockPaymentRepository()
	producer := new(MockEventProducer)
	producer.On("PublishPaymentCompleted", mock.Anything, mock.Anything).Return(nil)
	producer.On("PublishPaymentRefunded", mock.Anything, mock.Anything).Return(nil)

	svc := services.NewPaymentService(repo, producer)
	defer svc.Stop()

	req := models.ProcessPaymentRequest{
		OrderNumber:    "ORD-100",
		Amount:         150.00,
		Currency:       "USD",
		PaymentMethod:  "CARD_VISA",
		CustomerEmail:  "test@example.com",
		IdempotencyKey: "idem-100",
	}

	resp, err := svc.ProcessPayment(context.Background(), req)
	assert.NoError(t, err)
	assert.NotNil(t, resp)
	assert.Equal(t, "ORD-100", resp.OrderNumber)
	assert.Equal(t, models.PaymentStatusCompleted, resp.Status)
	assert.NotEmpty(t, resp.TransactionRef)

	// Verify Idempotency returns identical result
	resp2, err2 := svc.ProcessPayment(context.Background(), req)
	assert.NoError(t, err2)
	assert.Equal(t, resp.ID, resp2.ID)
	assert.Equal(t, resp.TransactionRef, resp2.TransactionRef)
}

func TestProcessPayment_Declined(t *testing.T) {
	repo := NewMockPaymentRepository()
	producer := new(MockEventProducer)
	producer.On("PublishPaymentFailed", mock.Anything, mock.Anything).Return(nil)

	svc := services.NewPaymentService(repo, producer)
	defer svc.Stop()

	req := models.ProcessPaymentRequest{
		OrderNumber:    "ORD-DECLINE-1",
		Amount:         75.00,
		Currency:       "USD",
		PaymentMethod:  "CARD_DECLINE",
		CustomerEmail:  "decline@example.com",
		IdempotencyKey: "idem-decline-1",
	}

	resp, err := svc.ProcessPayment(context.Background(), req)
	assert.NoError(t, err)
	assert.NotNil(t, resp)
	assert.Equal(t, models.PaymentStatusFailed, resp.Status)
	assert.Empty(t, resp.TransactionRef)
	assert.Contains(t, resp.FailureReason, "Payment declined")

	// Test specific decline profiles
	declineCases := []struct {
		method         string
		expectedReason string
	}{
		{"SIMULATED_DECLINED_INSUFFICIENT_FUNDS", "Do Not Honor (Code 51)"},
		{"SIMULATED_DECLINED_INCORRECT_PIN", "Invalid PIN/CVV (Code 55)"},
		{"SIMULATED_DECLINED_SUSPECTED_FRAUD", "Suspected Fraud (Code 59)"},
		{"SIMULATED_DECLINED_EXPIRED_CARD", "Expired Card (Code 54)"},
	}

	for _, tc := range declineCases {
		dResp, dErr := svc.ProcessPayment(context.Background(), models.ProcessPaymentRequest{
			OrderNumber:   "ORD-TEST-" + tc.method,
			Amount:        100.0,
			PaymentMethod: tc.method,
		})
		assert.NoError(t, dErr)
		assert.NotNil(t, dResp)
		assert.Equal(t, models.PaymentStatusFailed, dResp.Status)
		assert.Contains(t, dResp.FailureReason, tc.expectedReason)
	}
}

func TestRefundPayment_SuccessAndErrors(t *testing.T) {
	repo := NewMockPaymentRepository()
	producer := new(MockEventProducer)
	producer.On("PublishPaymentCompleted", mock.Anything, mock.Anything).Return(nil)
	producer.On("PublishPaymentRefunded", mock.Anything, mock.Anything).Return(nil)

	svc := services.NewPaymentService(repo, producer)
	defer svc.Stop()

	// 1. Refund non-existent payment
	_, err := svc.RefundPayment(context.Background(), models.RefundPaymentRequest{
		OrderNumber: "ORD-NOT-FOUND",
		Reason:      "Wrong item",
	})
	assert.Error(t, err)
	assert.Contains(t, err.Error(), "no payment found")

	// 2. Process valid payment first
	_, err = svc.ProcessPayment(context.Background(), models.ProcessPaymentRequest{
		OrderNumber:    "ORD-REFUND-1",
		Amount:         80.00,
		PaymentMethod:  "CARD_VISA",
		IdempotencyKey: "idem-ref-1",
	})
	assert.NoError(t, err)

	// 3. Successfully refund
	refunded, err := svc.RefundPayment(context.Background(), models.RefundPaymentRequest{
		OrderNumber: "ORD-REFUND-1",
		Reason:      "Customer request",
	})
	assert.NoError(t, err)
	assert.Equal(t, models.PaymentStatusRefunded, refunded.Status)

	// 4. Refund already refunded payment should fail
	_, err = svc.RefundPayment(context.Background(), models.RefundPaymentRequest{
		OrderNumber: "ORD-REFUND-1",
		Reason:      "Duplicate refund attempt",
	})
	assert.Error(t, err)
	assert.Contains(t, err.Error(), "cannot refund payment")
}

func TestGetPaymentQueries(t *testing.T) {
	repo := NewMockPaymentRepository()
	svc := services.NewPaymentService(repo, nil)
	defer svc.Stop()

	resp, err := svc.ProcessPayment(context.Background(), models.ProcessPaymentRequest{
		OrderNumber:   "ORD-LOOKUP",
		Amount:        45.00,
		PaymentMethod: "CARD_MASTERCARD",
	})
	assert.NoError(t, err)

	// By order number
	foundOrder, err := svc.GetPaymentByOrder(context.Background(), "ORD-LOOKUP")
	assert.NoError(t, err)
	assert.NotNil(t, foundOrder)
	assert.Equal(t, resp.ID, foundOrder.ID)

	// By ID
	foundID, err := svc.GetPaymentByID(context.Background(), resp.ID)
	assert.NoError(t, err)
	assert.NotNil(t, foundID)
	assert.Equal(t, "ORD-LOOKUP", foundID.OrderNumber)

	// Not found
	notFound, err := svc.GetPaymentByOrder(context.Background(), "ORD-NONE")
	assert.NoError(t, err)
	assert.Nil(t, notFound)
}

func TestFlushPendingOutbox(t *testing.T) {
	repo := NewMockPaymentRepository()
	producer := new(MockEventProducer)
	producer.On("PublishPaymentCompleted", mock.Anything, mock.Anything).Return(nil)
	producer.On("PublishPaymentRefunded", mock.Anything, mock.Anything).Return(nil)

	completedBytes, _ := json.Marshal(models.PaymentCompletedEvent{
		EventType:   "PAYMENT_COMPLETED",
		OrderNumber: "ORD-FLUSH-1",
		Amount:      50.0,
	})
	refundedBytes, _ := json.Marshal(models.PaymentRefundedEvent{
		EventType:   "PAYMENT_REFUNDED",
		OrderNumber: "ORD-FLUSH-2",
		Amount:      30.0,
	})

	_ = repo.SaveOutboxEvent(context.Background(), &models.OutboxEvent{
		ID:            uuid.New(),
		AggregateType: "PAYMENT",
		AggregateID:   "ORD-FLUSH-1",
		EventType:     "PAYMENT_COMPLETED",
		Payload:       string(completedBytes),
		Status:        "PENDING",
	})
	_ = repo.SaveOutboxEvent(context.Background(), &models.OutboxEvent{
		ID:            uuid.New(),
		AggregateType: "PAYMENT",
		AggregateID:   "ORD-FLUSH-2",
		EventType:     "PAYMENT_REFUNDED",
		Payload:       string(refundedBytes),
		Status:        "PENDING",
	})

	svc := services.NewPaymentService(repo, producer)
	defer svc.Stop()

	err := svc.FlushPendingOutbox(context.Background())
	assert.NoError(t, err)

	pending, _ := repo.GetPendingOutboxEvents(context.Background(), 10)
	assert.Empty(t, pending)
}
