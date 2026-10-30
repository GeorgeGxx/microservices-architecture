package kafka

import (
	"context"
	"encoding/json"
	"errors"
	"testing"

	"github.com/georgegxx/payments-service/internal/models"
	"github.com/segmentio/kafka-go"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/mock"
)

type mockMessageReader struct {
	mock.Mock
}

func (m *mockMessageReader) Config() kafka.ReaderConfig {
	return kafka.ReaderConfig{Topic: "orders-topic"}
}

func (m *mockMessageReader) FetchMessage(ctx context.Context) (kafka.Message, error) {
	args := m.Called(ctx)
	return args.Get(0).(kafka.Message), args.Error(1)
}

func (m *mockMessageReader) CommitMessages(ctx context.Context, msgs ...kafka.Message) error {
	args := m.Called(ctx, msgs)
	return args.Error(0)
}

func (m *mockMessageReader) Close() error {
	args := m.Called()
	return args.Error(0)
}

type mockPaymentProcessor struct {
	mock.Mock
}

func (m *mockPaymentProcessor) ProcessPayment(ctx context.Context, req models.ProcessPaymentRequest) (*models.ProcessPaymentResponse, error) {
	args := m.Called(ctx, req)
	if args.Get(0) == nil {
		return nil, args.Error(1)
	}
	return args.Get(0).(*models.ProcessPaymentResponse), args.Error(1)
}

func (m *mockPaymentProcessor) RefundPayment(ctx context.Context, req models.RefundPaymentRequest) (*models.Payment, error) {
	args := m.Called(ctx, req)
	if args.Get(0) == nil {
		return nil, args.Error(1)
	}
	return args.Get(0).(*models.Payment), args.Error(1)
}

func TestNewOrderEventConsumer(t *testing.T) {
	processor := new(mockPaymentProcessor)
	consumer := NewOrderEventConsumer([]string{"localhost:9092"}, "orders-topic", "test-group", processor)
	assert.NotNil(t, consumer)
	_ = consumer.Close()
}

func TestHandleMessage_PlacedOrderSuccess(t *testing.T) {
	mockReader := new(mockMessageReader)
	mockProcessor := new(mockPaymentProcessor)

	mockReader.On("CommitMessages", mock.Anything, mock.Anything).Return(nil)
	mockProcessor.On("ProcessPayment", mock.Anything, mock.MatchedBy(func(req models.ProcessPaymentRequest) bool {
		return req.OrderNumber == "ORD-100" && req.Amount == 150.0
	})).Return(&models.ProcessPaymentResponse{OrderNumber: "ORD-100"}, nil)

	consumer := &OrderEventConsumer{
		reader:    mockReader,
		processor: mockProcessor,
		stopChan:  make(chan struct{}),
	}

	payload := map[string]interface{}{
		"orderNumber":   "ORD-100",
		"status":        "PLACED",
		"totalAmount":   150.0,
		"paymentMethod": "CARD_VISA",
		"customerEmail": "user@example.com",
	}
	raw, _ := json.Marshal(payload)

	msg := kafka.Message{
		Key:   []byte("ORD-100"),
		Value: raw,
	}

	consumer.handleMessage(context.Background(), msg)
	mockReader.AssertExpectations(t)
	mockProcessor.AssertExpectations(t)
}

func TestHandleMessage_CompensatingRefundOnShipmentFailed(t *testing.T) {
	mockReader := new(mockMessageReader)
	mockProcessor := new(mockPaymentProcessor)

	mockReader.On("CommitMessages", mock.Anything, mock.Anything).Return(nil)
	mockProcessor.On("RefundPayment", mock.Anything, mock.MatchedBy(func(req models.RefundPaymentRequest) bool {
		return req.OrderNumber == "ORD-COMP-1" && req.Reason == "Address invalid"
	})).Return(&models.Payment{OrderNumber: "ORD-COMP-1", Status: models.PaymentStatusRefunded}, nil)

	consumer := &OrderEventConsumer{
		reader:    mockReader,
		processor: mockProcessor,
		stopChan:  make(chan struct{}),
	}

	payload := map[string]interface{}{
		"orderNumber": "ORD-COMP-1",
		"eventType":   "SHIPMENT_FAILED",
		"reason":      "Address invalid",
	}
	raw, _ := json.Marshal(payload)

	msg := kafka.Message{
		Key:   []byte("ORD-COMP-1"),
		Value: raw,
	}

	consumer.handleMessage(context.Background(), msg)
	mockReader.AssertExpectations(t)
	mockProcessor.AssertExpectations(t)
}

func TestHandleMessage_MalformedJSON(t *testing.T) {
	mockReader := new(mockMessageReader)
	mockProcessor := new(mockPaymentProcessor)

	mockReader.On("CommitMessages", mock.Anything, mock.Anything).Return(nil)

	consumer := &OrderEventConsumer{
		reader:    mockReader,
		processor: mockProcessor,
		stopChan:  make(chan struct{}),
	}

	msg := kafka.Message{
		Key:   []byte("ORD-BAD"),
		Value: []byte("{not-a-valid-json"),
	}

	consumer.handleMessage(context.Background(), msg)
	mockReader.AssertExpectations(t)
	mockProcessor.AssertNotCalled(t, "ProcessPayment")
}

func TestHandleMessage_IgnoredStatus(t *testing.T) {
	mockReader := new(mockMessageReader)
	mockProcessor := new(mockPaymentProcessor)

	mockReader.On("CommitMessages", mock.Anything, mock.Anything).Return(nil)

	consumer := &OrderEventConsumer{
		reader:    mockReader,
		processor: mockProcessor,
		stopChan:  make(chan struct{}),
	}

	payload := map[string]interface{}{
		"orderNumber": "ORD-DELIVERED",
		"status":      "DELIVERED",
	}
	raw, _ := json.Marshal(payload)

	msg := kafka.Message{
		Key:   []byte("ORD-DELIVERED"),
		Value: raw,
	}

	consumer.handleMessage(context.Background(), msg)
	mockReader.AssertExpectations(t)
	mockProcessor.AssertNotCalled(t, "ProcessPayment")
}

func TestHandleMessage_ProcessorError(t *testing.T) {
	mockReader := new(mockMessageReader)
	mockProcessor := new(mockPaymentProcessor)

	mockReader.On("CommitMessages", mock.Anything, mock.Anything).Return(nil)
	mockProcessor.On("ProcessPayment", mock.Anything, mock.Anything).Return(nil, errors.New("processor failure"))

	consumer := &OrderEventConsumer{
		reader:    mockReader,
		processor: mockProcessor,
		stopChan:  make(chan struct{}),
	}

	payload := map[string]interface{}{
		"orderNumber": "ORD-ERR",
		"status":      "PENDING_PAYMENT",
		"totalAmount": 75.0,
	}
	raw, _ := json.Marshal(payload)

	msg := kafka.Message{
		Key:   []byte("ORD-ERR"),
		Value: raw,
	}

	consumer.handleMessage(context.Background(), msg)
	mockReader.AssertExpectations(t)
	mockProcessor.AssertExpectations(t)
}
