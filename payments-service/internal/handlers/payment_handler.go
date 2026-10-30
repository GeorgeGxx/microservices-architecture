package handlers

import (
	"net/http"

	"github.com/georgegxx/payments-service/internal/models"
	"github.com/georgegxx/payments-service/internal/services"
	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
)

type PaymentHandler struct {
	service services.PaymentService
}

func NewPaymentHandler(service services.PaymentService) *PaymentHandler {
	return &PaymentHandler{service: service}
}

// ProcessPayment godoc
// @Summary Process a customer payment transaction
// @Description Creates and executes a payment charge with idempotency support and gateway simulation
// @Tags payments
// @Accept json
// @Produce json
// @Param Idempotency-Key header string false "Unique idempotency key for safe retries"
// @Param request body models.ProcessPaymentRequest true "Payment Details"
// @Success 200 {object} models.StandardResponse{data=models.ProcessPaymentResponse}
// @Failure 400 {object} models.StandardResponse
// @Failure 500 {object} models.StandardResponse
// @Router /api/v1/payments/process [post]
func (h *PaymentHandler) ProcessPayment(c *gin.Context) {
	var req models.ProcessPaymentRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, models.StandardResponse{
			Success: false,
			Message: "Invalid payment request payload: " + err.Error(),
		})
		return
	}

	// Prefer Idempotency-Key header if provided
	if headerKey := c.GetHeader("Idempotency-Key"); headerKey != "" {
		req.IdempotencyKey = headerKey
	}

	resp, err := h.service.ProcessPayment(c.Request.Context(), req)
	if err != nil {
		c.JSON(http.StatusInternalServerError, models.StandardResponse{
			Success: false,
			Message: "Payment processing error: " + err.Error(),
		})
		return
	}

	c.JSON(http.StatusOK, models.StandardResponse{
		Success: true,
		Message: "Payment processed successfully",
		Data:    resp,
	})
}

// RefundPayment godoc
// @Summary Refund an existing payment transaction
// @Description Reverses a completed payment for an order and records refund telemetry
// @Tags payments
// @Accept json
// @Produce json
// @Param request body models.RefundPaymentRequest true "Refund Request"
// @Success 200 {object} models.StandardResponse{data=models.Payment}
// @Failure 400 {object} models.StandardResponse
// @Failure 500 {object} models.StandardResponse
// @Router /api/v1/payments/refund [post]
func (h *PaymentHandler) RefundPayment(c *gin.Context) {
	var req models.RefundPaymentRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, models.StandardResponse{
			Success: false,
			Message: "Invalid refund payload: " + err.Error(),
		})
		return
	}

	payment, err := h.service.RefundPayment(c.Request.Context(), req)
	if err != nil {
		c.JSON(http.StatusBadRequest, models.StandardResponse{
			Success: false,
			Message: err.Error(),
		})
		return
	}

	c.JSON(http.StatusOK, models.StandardResponse{
		Success: true,
		Message: "Payment refunded successfully",
		Data:    payment,
	})
}

// GetPaymentByOrder godoc
// @Summary Retrieve payment details by Order Number
// @Description Returns the latest payment record associated with a given order
// @Tags payments
// @Produce json
// @Param orderNumber path string true "Order Number"
// @Success 200 {object} models.StandardResponse{data=models.Payment}
// @Failure 404 {object} models.StandardResponse
// @Failure 500 {object} models.StandardResponse
// @Router /api/v1/payments/order/{orderNumber} [get]
func (h *PaymentHandler) GetPaymentByOrder(c *gin.Context) {
	orderNumber := c.Param("orderNumber")
	if orderNumber == "" {
		c.JSON(http.StatusBadRequest, models.StandardResponse{
			Success: false,
			Message: "orderNumber parameter is required",
		})
		return
	}

	payment, err := h.service.GetPaymentByOrder(c.Request.Context(), orderNumber)
	if err != nil {
		c.JSON(http.StatusInternalServerError, models.StandardResponse{
			Success: false,
			Message: err.Error(),
		})
		return
	}
	if payment == nil {
		c.JSON(http.StatusNotFound, models.StandardResponse{
			Success: false,
			Message: "No payment found for order: " + orderNumber,
		})
		return
	}

	c.JSON(http.StatusOK, models.StandardResponse{
		Success: true,
		Message: "Payment retrieved successfully",
		Data:    payment,
	})
}

// GetPaymentByID godoc
// @Summary Retrieve payment details by ID
// @Description Returns a payment transaction by its UUID
// @Tags payments
// @Produce json
// @Param id path string true "Payment UUID"
// @Success 200 {object} models.StandardResponse{data=models.Payment}
// @Failure 400 {object} models.StandardResponse
// @Failure 404 {object} models.StandardResponse
// @Failure 500 {object} models.StandardResponse
// @Router /api/v1/payments/{id} [get]
func (h *PaymentHandler) GetPaymentByID(c *gin.Context) {
	idStr := c.Param("id")
	id, err := uuid.Parse(idStr)
	if err != nil {
		c.JSON(http.StatusBadRequest, models.StandardResponse{
			Success: false,
			Message: "Invalid UUID format",
		})
		return
	}

	payment, err := h.service.GetPaymentByID(c.Request.Context(), id)
	if err != nil {
		c.JSON(http.StatusInternalServerError, models.StandardResponse{
			Success: false,
			Message: err.Error(),
		})
		return
	}
	if payment == nil {
		c.JSON(http.StatusNotFound, models.StandardResponse{
			Success: false,
			Message: "Payment not found",
		})
		return
	}

	c.JSON(http.StatusOK, models.StandardResponse{
		Success: true,
		Message: "Payment retrieved successfully",
		Data:    payment,
	})
}

// Health godoc
// @Summary Service Health Check
// @Description Checks operational readiness and liveness of payments-service
// @Tags system
// @Produce json
// @Success 200 {object} map[string]interface{}
// @Router /health [get]
func (h *PaymentHandler) Health(c *gin.Context) {
	c.JSON(http.StatusOK, gin.H{
		"status":  "UP",
		"service": "payments-service",
		"engine":  "go1.26",
		"version": "1.0.0",
	})
}
