package handlers_test

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/georgegxx/payments-service/internal/handlers"
	"github.com/georgegxx/payments-service/internal/models"
	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/mock"
)

type MockPaymentService struct {
	mock.Mock
}

func (m *MockPaymentService) ProcessPayment(ctx context.Context, req models.ProcessPaymentRequest) (*models.ProcessPaymentResponse, error) {
	args := m.Called(ctx, req)
	if args.Get(0) == nil {
		return nil, args.Error(1)
	}
	return args.Get(0).(*models.ProcessPaymentResponse), args.Error(1)
}

func (m *MockPaymentService) RefundPayment(ctx context.Context, req models.RefundPaymentRequest) (*models.Payment, error) {
	args := m.Called(ctx, req)
	if args.Get(0) == nil {
		return nil, args.Error(1)
	}
	return args.Get(0).(*models.Payment), args.Error(1)
}

func (m *MockPaymentService) GetPaymentByOrder(ctx context.Context, orderNumber string) (*models.Payment, error) {
	args := m.Called(ctx, orderNumber)
	if args.Get(0) == nil {
		return nil, args.Error(1)
	}
	return args.Get(0).(*models.Payment), args.Error(1)
}

func (m *MockPaymentService) GetPaymentByID(ctx context.Context, id uuid.UUID) (*models.Payment, error) {
	args := m.Called(ctx, id)
	if args.Get(0) == nil {
		return nil, args.Error(1)
	}
	return args.Get(0).(*models.Payment), args.Error(1)
}

func (m *MockPaymentService) Stop() {}

func setupRouter(h *handlers.PaymentHandler) *gin.Engine {
	gin.SetMode(gin.TestMode)
	r := gin.New()
	r.GET("/health", h.Health)
	v1 := r.Group("/api/v1/payments")
	{
		v1.POST("/process", h.ProcessPayment)
		v1.POST("/refund", h.RefundPayment)
		v1.GET("/order/:orderNumber", h.GetPaymentByOrder)
		v1.GET("/:id", h.GetPaymentByID)
	}
	return r
}

func TestHealthEndpoint(t *testing.T) {
	h := handlers.NewPaymentHandler(new(MockPaymentService))
	r := setupRouter(h)

	req := httptest.NewRequest(http.MethodGet, "/health", nil)
	w := httptest.NewRecorder()
	r.ServeHTTP(w, req)

	assert.Equal(t, http.StatusOK, w.Code)
	assert.Contains(t, w.Body.String(), "UP")
}

func TestProcessPaymentEndpoint_Success(t *testing.T) {
	mockSvc := new(MockPaymentService)
	h := handlers.NewPaymentHandler(mockSvc)
	r := setupRouter(h)

	expectedResp := &models.ProcessPaymentResponse{
		ID:             uuid.New(),
		OrderNumber:    "ORD-TEST",
		Amount:         100.0,
		Status:         models.PaymentStatusCompleted,
		TransactionRef: "TXN-1234",
	}

	mockSvc.On("ProcessPayment", mock.Anything, mock.MatchedBy(func(req models.ProcessPaymentRequest) bool {
		return req.OrderNumber == "ORD-TEST" && req.IdempotencyKey == "header-idem-123"
	})).Return(expectedResp, nil)

	body, _ := json.Marshal(models.ProcessPaymentRequest{
		OrderNumber:   "ORD-TEST",
		Amount:        100.0,
		PaymentMethod: "CARD_VISA",
	})

	req := httptest.NewRequest(http.MethodPost, "/api/v1/payments/process", bytes.NewReader(body))
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Idempotency-Key", "header-idem-123")
	w := httptest.NewRecorder()
	r.ServeHTTP(w, req)

	assert.Equal(t, http.StatusOK, w.Code)
	assert.Contains(t, w.Body.String(), "TXN-1234")
}

func TestProcessPaymentEndpoint_BadInput(t *testing.T) {
	h := handlers.NewPaymentHandler(new(MockPaymentService))
	r := setupRouter(h)

	body, _ := json.Marshal(map[string]interface{}{"amount": -5})
	req := httptest.NewRequest(http.MethodPost, "/api/v1/payments/process", bytes.NewReader(body))
	req.Header.Set("Content-Type", "application/json")
	w := httptest.NewRecorder()
	r.ServeHTTP(w, req)

	assert.Equal(t, http.StatusBadRequest, w.Code)
}

func TestProcessPaymentEndpoint_ServiceError(t *testing.T) {
	mockSvc := new(MockPaymentService)
	h := handlers.NewPaymentHandler(mockSvc)
	r := setupRouter(h)

	mockSvc.On("ProcessPayment", mock.Anything, mock.Anything).Return(nil, errors.New("db failure"))

	body, _ := json.Marshal(models.ProcessPaymentRequest{
		OrderNumber:   "ORD-ERR",
		Amount:        50.0,
		PaymentMethod: "CARD_VISA",
	})
	req := httptest.NewRequest(http.MethodPost, "/api/v1/payments/process", bytes.NewReader(body))
	req.Header.Set("Content-Type", "application/json")
	w := httptest.NewRecorder()
	r.ServeHTTP(w, req)

	assert.Equal(t, http.StatusInternalServerError, w.Code)
}

func TestRefundPaymentEndpoint_Success(t *testing.T) {
	mockSvc := new(MockPaymentService)
	h := handlers.NewPaymentHandler(mockSvc)
	r := setupRouter(h)

	mockSvc.On("RefundPayment", mock.Anything, mock.MatchedBy(func(req models.RefundPaymentRequest) bool {
		return req.OrderNumber == "ORD-REF"
	})).Return(&models.Payment{OrderNumber: "ORD-REF", Status: models.PaymentStatusRefunded}, nil)

	body, _ := json.Marshal(models.RefundPaymentRequest{OrderNumber: "ORD-REF", Reason: "Damaged item"})
	req := httptest.NewRequest(http.MethodPost, "/api/v1/payments/refund", bytes.NewReader(body))
	req.Header.Set("Content-Type", "application/json")
	w := httptest.NewRecorder()
	r.ServeHTTP(w, req)

	assert.Equal(t, http.StatusOK, w.Code)
	assert.Contains(t, w.Body.String(), "REFUNDED")
}

func TestRefundPaymentEndpoint_Errors(t *testing.T) {
	mockSvc := new(MockPaymentService)
	h := handlers.NewPaymentHandler(mockSvc)
	r := setupRouter(h)

	// Bad input JSON
	reqBad := httptest.NewRequest(http.MethodPost, "/api/v1/payments/refund", bytes.NewReader([]byte("invalid json")))
	reqBad.Header.Set("Content-Type", "application/json")
	wBad := httptest.NewRecorder()
	r.ServeHTTP(wBad, reqBad)
	assert.Equal(t, http.StatusBadRequest, wBad.Code)

	// Service error
	mockSvc.On("RefundPayment", mock.Anything, mock.Anything).Return(nil, errors.New("cannot refund non-completed order"))
	body, _ := json.Marshal(models.RefundPaymentRequest{OrderNumber: "ORD-FAIL"})
	reqFail := httptest.NewRequest(http.MethodPost, "/api/v1/payments/refund", bytes.NewReader(body))
	reqFail.Header.Set("Content-Type", "application/json")
	wFail := httptest.NewRecorder()
	r.ServeHTTP(wFail, reqFail)
	assert.Equal(t, http.StatusBadRequest, wFail.Code)
}

func TestGetPaymentByOrderEndpoint(t *testing.T) {
	mockSvc := new(MockPaymentService)
	h := handlers.NewPaymentHandler(mockSvc)
	r := setupRouter(h)

	mockSvc.On("GetPaymentByOrder", mock.Anything, "ORD-OK").Return(&models.Payment{
		OrderNumber: "ORD-OK",
		Status:      models.PaymentStatusCompleted,
	}, nil)
	mockSvc.On("GetPaymentByOrder", mock.Anything, "ORD-NOT-FOUND").Return(nil, nil)
	mockSvc.On("GetPaymentByOrder", mock.Anything, "ORD-ERROR").Return(nil, errors.New("query error"))

	// Found
	req := httptest.NewRequest(http.MethodGet, "/api/v1/payments/order/ORD-OK", nil)
	w := httptest.NewRecorder()
	r.ServeHTTP(w, req)
	assert.Equal(t, http.StatusOK, w.Code)

	// Not Found
	req2 := httptest.NewRequest(http.MethodGet, "/api/v1/payments/order/ORD-NOT-FOUND", nil)
	w2 := httptest.NewRecorder()
	r.ServeHTTP(w2, req2)
	assert.Equal(t, http.StatusNotFound, w2.Code)

	// Error
	req3 := httptest.NewRequest(http.MethodGet, "/api/v1/payments/order/ORD-ERROR", nil)
	w3 := httptest.NewRecorder()
	r.ServeHTTP(w3, req3)
	assert.Equal(t, http.StatusInternalServerError, w3.Code)
}

func TestGetPaymentByIDEndpoint(t *testing.T) {
	mockSvc := new(MockPaymentService)
	h := handlers.NewPaymentHandler(mockSvc)
	r := setupRouter(h)

	testID := uuid.New()
	mockSvc.On("GetPaymentByID", mock.Anything, testID).Return(&models.Payment{
		ID:          testID,
		OrderNumber: "ORD-UUID",
	}, nil)

	notFoundID := uuid.New()
	mockSvc.On("GetPaymentByID", mock.Anything, notFoundID).Return(nil, nil)

	errID := uuid.New()
	mockSvc.On("GetPaymentByID", mock.Anything, errID).Return(nil, errors.New("db error"))

	// Valid ID
	req := httptest.NewRequest(http.MethodGet, "/api/v1/payments/"+testID.String(), nil)
	w := httptest.NewRecorder()
	r.ServeHTTP(w, req)
	assert.Equal(t, http.StatusOK, w.Code)

	// Not Found
	reqNotFound := httptest.NewRequest(http.MethodGet, "/api/v1/payments/"+notFoundID.String(), nil)
	wNotFound := httptest.NewRecorder()
	r.ServeHTTP(wNotFound, reqNotFound)
	assert.Equal(t, http.StatusNotFound, wNotFound.Code)

	// Error
	reqErr := httptest.NewRequest(http.MethodGet, "/api/v1/payments/"+errID.String(), nil)
	wErr := httptest.NewRecorder()
	r.ServeHTTP(wErr, reqErr)
	assert.Equal(t, http.StatusInternalServerError, wErr.Code)

	// Invalid UUID
	req2 := httptest.NewRequest(http.MethodGet, "/api/v1/payments/not-a-valid-uuid", nil)
	w2 := httptest.NewRecorder()
	r.ServeHTTP(w2, req2)
	assert.Equal(t, http.StatusBadRequest, w2.Code)
}
