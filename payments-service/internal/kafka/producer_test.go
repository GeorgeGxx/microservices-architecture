package kafka

import (
	"context"
	"errors"
	"testing"
	"time"

	"github.com/georgegxx/payments-service/internal/models"
	"github.com/segmentio/kafka-go"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/mock"
)

type mockMessageWriter struct {
	mock.Mock
}

func (m *mockMessageWriter) WriteMessages(ctx context.Context, msgs ...kafka.Message) error {
	args := m.Called(ctx, msgs)
	return args.Error(0)
}

func (m *mockMessageWriter) Close() error {
	args := m.Called()
	return args.Error(0)
}

func TestNewEventProducer(t *testing.T) {
	prod := NewEventProducer([]string{"localhost:9092"}, "test-topic")
	assert.NotNil(t, prod)
	_ = prod.Close()
}

func TestPublishPaymentCompleted_Success(t *testing.T) {
	mockWriter := new(mockMessageWriter)
	mockWriter.On("WriteMessages", mock.Anything, mock.Anything).Return(nil)

	prod := &eventProducer{
		writer: mockWriter,
		topic:  "payments-topic",
	}

	event := models.PaymentCompletedEvent{
		PaymentID:      "pay-123",
		OrderNumber:    "ORD-1",
		Amount:         100.0,
		TransactionRef: "TXN-1",
		Timestamp:      time.Now(),
	}

	err := prod.PublishPaymentCompleted(context.Background(), event)
	assert.NoError(t, err)
	mockWriter.AssertExpectations(t)
}

func TestPublishPaymentCompleted_Error(t *testing.T) {
	mockWriter := new(mockMessageWriter)
	mockWriter.On("WriteMessages", mock.Anything, mock.Anything).Return(errors.New("kafka write failed"))

	prod := &eventProducer{
		writer: mockWriter,
		topic:  "payments-topic",
	}

	event := models.PaymentCompletedEvent{
		PaymentID:      "pay-123",
		OrderNumber:    "ORD-1",
		Amount:         100.0,
		TransactionRef: "TXN-1",
		Timestamp:      time.Now(),
	}

	err := prod.PublishPaymentCompleted(context.Background(), event)
	assert.Error(t, err)
	assert.Contains(t, err.Error(), "kafka write failed")
}

func TestPublishPaymentFailed_Success(t *testing.T) {
	mockWriter := new(mockMessageWriter)
	mockWriter.On("WriteMessages", mock.Anything, mock.Anything).Return(nil)

	prod := &eventProducer{
		writer: mockWriter,
		topic:  "payments-topic",
	}

	event := models.PaymentFailedEvent{
		OrderNumber: "ORD-2",
		Amount:      50.0,
		Reason:      "insufficient funds",
		ErrorCode:   "PAYMENT_DECLINED",
		Timestamp:   time.Now(),
	}

	err := prod.PublishPaymentFailed(context.Background(), event)
	assert.NoError(t, err)
	mockWriter.AssertExpectations(t)
}

func TestPublishPaymentRefunded_Success(t *testing.T) {
	mockWriter := new(mockMessageWriter)
	mockWriter.On("WriteMessages", mock.Anything, mock.Anything).Return(nil)

	prod := &eventProducer{
		writer: mockWriter,
		topic:  "payments-topic",
	}

	event := models.PaymentRefundedEvent{
		EventType:   "PAYMENT_REFUNDED",
		Status:      "REFUNDED",
		OrderNumber: "ORD-3",
		Amount:      50.0,
		Reason:      "Shipment failed",
		Timestamp:   time.Now(),
	}

	err := prod.PublishPaymentRefunded(context.Background(), event)
	assert.NoError(t, err)
	mockWriter.AssertExpectations(t)
}

func TestEventProducer_Close(t *testing.T) {
	mockWriter := new(mockMessageWriter)
	mockWriter.On("Close").Return(nil)

	prod := &eventProducer{
		writer: mockWriter,
		topic:  "payments-topic",
	}

	err := prod.Close()
	assert.NoError(t, err)
	mockWriter.AssertExpectations(t)
}
