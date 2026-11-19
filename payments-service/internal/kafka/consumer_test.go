package kafka

import (
	"context"
	"encoding/json"
	"errors"
	"testing"

	"github.com/georgegxx/payments-service/internal/models"
	"github.com/georgegxx/payments-service/internal/repository"
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

type consumerRepositoryStub struct {
	repository.PaymentRepository
	messageProcessed bool
	checkErr         error
	recorded         *models.ProcessedMessage
}

func (r *consumerRepositoryStub) IsMessageProcessed(context.Context, string) (bool, error) {
	return r.messageProcessed, r.checkErr
}

func (r *consumerRepositoryStub) RecordProcessedMessage(_ context.Context, message *models.ProcessedMessage) error {
	r.recorded = message
	return nil
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

func TestOrderEventConsumerStartStopsWhenContextIsCancelled(t *testing.T) {
	reader := new(mockMessageReader)
	ctx, cancel := context.WithCancel(context.Background())
	reader.On("FetchMessage", mock.Anything).Run(func(mock.Arguments) { cancel() }).Return(kafka.Message{}, context.Canceled).Once()
	consumer := &OrderEventConsumer{reader: reader, processor: new(mockPaymentProcessor), stopChan: make(chan struct{})}

	consumer.Start(ctx)

	reader.AssertExpectations(t)
}

func TestOrderEventConsumerStartStopsOnStopSignal(t *testing.T) {
	reader := new(mockMessageReader)
	stopChan := make(chan struct{})
	close(stopChan)
	consumer := &OrderEventConsumer{reader: reader, processor: new(mockPaymentProcessor), stopChan: stopChan}

	consumer.Start(context.Background())

	reader.AssertNotCalled(t, "FetchMessage", mock.Anything)
}

func TestHandleMessageDeduplicatesProcessedEvent(t *testing.T) {
	reader := new(mockMessageReader)
	processor := new(mockPaymentProcessor)
	repo := &consumerRepositoryStub{messageProcessed: true}
	reader.On("CommitMessages", mock.Anything, mock.Anything).Return(nil).Once()
	consumer := &OrderEventConsumer{reader: reader, processor: processor, repo: repo, stopChan: make(chan struct{})}
	message := kafka.Message{Key: []byte("ORD-DUP"), Value: []byte(`{"orderNumber":"ORD-DUP","status":"PLACED"}`)}

	assert.NoError(t, consumer.handleMessage(context.Background(), message))
	reader.AssertExpectations(t)
	processor.AssertNotCalled(t, "ProcessPayment", mock.Anything, mock.Anything)
}

func TestHandleMessageRecordsSuccessfulEvent(t *testing.T) {
	reader := new(mockMessageReader)
	processor := new(mockPaymentProcessor)
	repo := &consumerRepositoryStub{}
	reader.On("CommitMessages", mock.Anything, mock.Anything).Return(nil).Once()
	processor.On("ProcessPayment", mock.Anything, mock.Anything).Return(&models.ProcessPaymentResponse{OrderNumber: "ORD-IDEMP"}, nil).Once()
	consumer := &OrderEventConsumer{reader: reader, processor: processor, repo: repo, stopChan: make(chan struct{})}
	message := kafka.Message{Key: []byte("ORD-IDEMP"), Value: []byte(`{"orderNumber":"ORD-IDEMP","status":"PLACED"}`)}

	assert.NoError(t, consumer.handleMessage(context.Background(), message))
	assert.NotNil(t, repo.recorded)
	assert.Equal(t, "ORD-IDEMP:PLACED:", repo.recorded.MessageID)
	assert.Equal(t, "payments-service", repo.recorded.ConsumerID)
	reader.AssertExpectations(t)
	processor.AssertExpectations(t)
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

	// In a reliable consumer, CommitMessages must NOT be called if processing returns an error
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

	err := consumer.handleMessage(context.Background(), msg)
	assert.Error(t, err)
	mockReader.AssertNotCalled(t, "CommitMessages")
	mockProcessor.AssertExpectations(t)
}

func TestHandleMessage_CloudEventEnvelope(t *testing.T) {
	mockReader := new(mockMessageReader)
	mockProcessor := new(mockPaymentProcessor)

	mockReader.On("CommitMessages", mock.Anything, mock.Anything).Return(nil)
	mockProcessor.On("ProcessPayment", mock.Anything, mock.MatchedBy(func(req models.ProcessPaymentRequest) bool {
		return req.OrderNumber == "ORD-CE-999" && req.Amount == 299.99
	})).Return(&models.ProcessPaymentResponse{OrderNumber: "ORD-CE-999"}, nil)

	consumer := &OrderEventConsumer{
		reader:    mockReader,
		processor: mockProcessor,
		stopChan:  make(chan struct{}),
	}

	cloudEvent := map[string]interface{}{
		"specversion": "1.0",
		"id":          "evt-uuid-1234",
		"type":        "com.microservices.orders.order.created.v1",
		"source":      "/orders-service",
		"data": map[string]interface{}{
			"orderNumber":   "ORD-CE-999",
			"status":        "PLACED",
			"totalAmount":   299.99,
			"paymentMethod": "CARD_VISA",
			"customerEmail": "ce@example.com",
		},
	}
	raw, _ := json.Marshal(cloudEvent)

	msg := kafka.Message{
		Key:   []byte("ORD-CE-999"),
		Value: raw,
		Headers: []kafka.Header{
			{Key: "ce_id", Value: []byte("evt-uuid-1234")},
		},
	}

	err := consumer.handleMessage(context.Background(), msg)
	assert.NoError(t, err)
	mockReader.AssertExpectations(t)
	mockProcessor.AssertExpectations(t)
}
