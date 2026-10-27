package services_test

import (
	"context"
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
	payments map[string]*models.Payment
	mu       sync.RWMutex
}

func NewMockPaymentRepository() *MockPaymentRepository {
	return &MockPaymentRepository{
		payments: make(map[string]*models.Payment),
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

func (m *MockEventProducer) Close() error {
	return nil
}

func TestProcessPayment_Success(t *testing.T) {
	repo := NewMockPaymentRepository()
	producer := new(MockEventProducer)
	producer.On("PublishPaymentCompleted", mock.Anything, mock.Anything).Return(nil)

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
}

func TestRefundPayment_SuccessAndErrors(t *testing.T) {
	repo := NewMockPaymentRepository()
	producer := new(MockEventProducer)
	producer.On("PublishPaymentCompleted", mock.Anything, mock.Anything).Return(nil)

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
