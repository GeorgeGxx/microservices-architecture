package services

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"log"
	"math"
	"strings"
	"sync"
	"time"

	"github.com/georgegxx/payments-service/internal/kafka"
	"github.com/georgegxx/payments-service/internal/metrics"
	"github.com/georgegxx/payments-service/internal/models"
	"github.com/georgegxx/payments-service/internal/repository"
	"github.com/google/uuid"
)

type PaymentService interface {
	ProcessPayment(ctx context.Context, req models.ProcessPaymentRequest) (*models.ProcessPaymentResponse, error)
	RefundPayment(ctx context.Context, req models.RefundPaymentRequest) (*models.Payment, error)
	GetPaymentByOrder(ctx context.Context, orderNumber string) (*models.Payment, error)
	GetPaymentByID(ctx context.Context, id uuid.UUID) (*models.Payment, error)
	FlushPendingOutbox(ctx context.Context) error
	Stop()
}

type paymentService struct {
	repo      repository.PaymentRepository
	producer  kafka.EventProducer
	auditChan chan *models.PaymentAuditLog
	workerWg  sync.WaitGroup
	stopChan  chan struct{}
	stopOnce  sync.Once
}

const (
	auditQueueSize = 500
	auditWorkers   = 3
)

func normalizePaymentMethodLabel(method string) string {
	upper := strings.ToUpper(strings.TrimSpace(method))
	switch {
	case upper == "CARD_VISA" || upper == "VISA":
		return "CARD_VISA"
	case upper == "CARD_MASTERCARD" || upper == "MASTERCARD":
		return "CARD_MASTERCARD"
	case upper == "CARD_AMEX" || upper == "AMEX":
		return "CARD_AMEX"
	case upper == "PAYPAL":
		return "PAYPAL"
	case upper == "APPLE_PAY":
		return "APPLE_PAY"
	case strings.Contains(upper, "DECLINE"):
		return "SIMULATED_DECLINE"
	default:
		return "OTHER"
	}
}

func normalizeRefundReasonLabel(reason string) string {
	lower := strings.ToLower(strings.TrimSpace(reason))
	switch {
	case lower == "":
		return "general"
	case strings.Contains(lower, "cancel"):
		return "customer_cancellation"
	case strings.Contains(lower, "damage") || strings.Contains(lower, "defect"):
		return "damaged_item"
	case strings.Contains(lower, "fraud"):
		return "fraud_prevention"
	case strings.Contains(lower, "shipment") || strings.Contains(lower, "delivery") || strings.Contains(lower, "fulfillment"):
		return "fulfillment_compensation"
	default:
		return "other"
	}
}

func NewPaymentService(repo repository.PaymentRepository, producer kafka.EventProducer) PaymentService {
	svc := &paymentService{
		repo:      repo,
		producer:  producer,
		auditChan: make(chan *models.PaymentAuditLog, auditQueueSize),
		stopChan:  make(chan struct{}),
	}

	// Launch background worker pool using goroutines for audit logging
	for i := 1; i <= auditWorkers; i++ {
		svc.workerWg.Add(1)
		go svc.auditWorker(i)
	}

	// Launch background worker for Transactional Outbox retry drainer
	svc.workerWg.Add(1)
	go svc.outboxDrainerWorker()

	return svc
}

func (s *paymentService) auditWorker(workerID int) {
	defer s.workerWg.Done()
	log.Printf("[PaymentService] Audit worker goroutine #%d started", workerID)

	for {
		select {
		case <-s.stopChan:
			// Drain remaining queued logs without closing auditChan concurrently
			for {
				select {
				case logItem := <-s.auditChan:
					if logItem != nil {
						_ = s.repo.CreateAuditLog(context.Background(), logItem)
					}
				default:
					log.Printf("[PaymentService] Audit worker goroutine #%d exited", workerID)
					return
				}
			}
		case logItem, ok := <-s.auditChan:
			if !ok {
				return
			}
			metrics.AuditEventsDispatched.Inc()
			if err := s.repo.CreateAuditLog(context.Background(), logItem); err != nil {
				log.Printf("[PaymentService] Worker #%d failed to save audit log: %v", workerID, err)
			}
		}
	}
}

func (s *paymentService) dispatchAudit(paymentID uuid.UUID, action, details string) {
	auditItem := &models.PaymentAuditLog{
		ID:        uuid.New(),
		PaymentID: paymentID,
		Action:    action,
		Details:   details,
		CreatedAt: time.Now().UTC(),
	}

	select {
	case <-s.stopChan:
		_ = s.repo.CreateAuditLog(context.Background(), auditItem)
		return
	default:
	}

	select {
	case s.auditChan <- auditItem:
		// Dispatched to worker pool
	default:
		// Channel full, handle without blocking payment path
		s.workerWg.Add(1)
		go func(item *models.PaymentAuditLog) {
			defer s.workerWg.Done()
			_ = s.repo.CreateAuditLog(context.Background(), item)
		}(auditItem)
	}
}

func (s *paymentService) ProcessPayment(ctx context.Context, req models.ProcessPaymentRequest) (*models.ProcessPaymentResponse, error) {
	methodLabel := normalizePaymentMethodLabel(req.PaymentMethod)
	timer := metrics.PaymentProcessingDuration.WithLabelValues(methodLabel)
	startTime := time.Now()
	defer func() {
		timer.Observe(time.Since(startTime).Seconds())
	}()

	// 1. Idempotency Check
	if req.IdempotencyKey != "" {
		existing, err := s.repo.FindByIdempotencyKey(ctx, req.IdempotencyKey)
		if err != nil {
			return nil, fmt.Errorf("error verifying idempotency: %w", err)
		}
		if existing != nil {
			log.Printf("[PaymentService] Idempotency match for key '%s', returning existing payment %s", req.IdempotencyKey, existing.ID)
			return s.toProcessPaymentResponse(existing), nil
		}
	}

	// 2. Gateway Simulation & Outbox Event Construction
	payment := s.initPaymentRecord(req)
	simulatePaymentGateway(payment, req.PaymentMethod, req.Amount)
	outboxEvent, err := s.buildSagaOutboxEvent(req, payment)
	if err != nil {
		return nil, fmt.Errorf("failed to serialize payment outbox event: %w", err)
	}

	// 3. Persist Payment and OutboxEvent atomically in PostgreSQL 18
	if err := s.repo.CreatePaymentWithOutbox(ctx, payment, outboxEvent); err != nil {
		return nil, fmt.Errorf("failed to persist payment transaction in database: %w", err)
	}

	// 4. Async Audit Log via Goroutines
	s.dispatchAudit(payment.ID, string(payment.Status), fmt.Sprintf("Processed charge for order %s, amount %.2f %s", payment.OrderNumber, payment.Amount, payment.Currency))

	// 5. Trigger Outbox Relay (single publication path; no duplicate direct Kafka send)
	if s.producer != nil && outboxEvent != nil {
		s.workerWg.Add(1)
		go func(ev *models.OutboxEvent) {
			defer s.workerWg.Done()
			s.publishSingleOutboxEvent(context.Background(), ev)
		}(outboxEvent)
	}

	return s.toProcessPaymentResponse(payment), nil
}

func isPaymentDeclined(paymentMethod string, amount float64) bool {
	if amount == 9999.99 {
		return true
	}
	pmUpper := strings.ToUpper(paymentMethod)
	return strings.Contains(pmUpper, "DECLINE") || strings.HasPrefix(pmUpper, "SIMULATED_DECLINED")
}

func resolveDeclineReason(paymentMethod string) string {
	pmUpper := strings.ToUpper(paymentMethod)
	switch {
	case strings.Contains(pmUpper, "INSUFFICIENT_FUNDS") || strings.Contains(pmUpper, "NO_CREDIT"):
		return "Do Not Honor (Code 51): Insufficient funds / Credit limit exceeded"
	case strings.Contains(pmUpper, "PIN") || strings.Contains(pmUpper, "NIP") || strings.Contains(pmUpper, "CVV"):
		return "Invalid PIN/CVV (Code 55): Security authentication failed or incorrect PIN"
	case strings.Contains(pmUpper, "FRAUD") || strings.Contains(pmUpper, "SUSPECTED"):
		return "Suspected Fraud (Code 59): Security card hold triggered by issuing bank"
	case strings.Contains(pmUpper, "EXPIRED"):
		return "Expired Card (Code 54): Card validity period expired"
	default:
		return "Payment declined (Code 05): General transaction decline by issuer"
	}
}

func simulatePaymentGateway(payment *models.Payment, paymentMethod string, amount float64) {
	methodLabel := normalizePaymentMethodLabel(paymentMethod)
	if isPaymentDeclined(paymentMethod, amount) {
		payment.Status = models.PaymentStatusFailed
		payment.FailureReason = resolveDeclineReason(paymentMethod)
		payment.TransactionRef = ""
		metrics.PaymentsProcessedTotal.WithLabelValues("FAILED", methodLabel).Inc()
		return
	}

	payment.Status = models.PaymentStatusCompleted
	payment.TransactionRef = fmt.Sprintf("TXN-%s", uuid.New().String()[:8])
	payment.FailureReason = ""
	metrics.PaymentsProcessedTotal.WithLabelValues("COMPLETED", methodLabel).Inc()
}

func (s *paymentService) initPaymentRecord(req models.ProcessPaymentRequest) *models.Payment {
	now := time.Now().UTC()
	payment := &models.Payment{
		ID:             uuid.New(),
		OrderNumber:    req.OrderNumber,
		Amount:         math.Round(req.Amount*100) / 100,
		RefundedAmount: 0,
		Currency:       strings.ToUpper(strings.TrimSpace(req.Currency)),
		PaymentMethod:  req.PaymentMethod,
		IdempotencyKey: req.IdempotencyKey,
		CustomerEmail:  req.CustomerEmail,
		CreatedAt:      now,
		UpdatedAt:      now,
	}
	if payment.Currency == "" {
		payment.Currency = "USD"
	}
	if payment.IdempotencyKey == "" {
		payment.IdempotencyKey = "gen-" + uuid.New().String()
	}
	return payment
}

func (s *paymentService) buildSagaOutboxEvent(req models.ProcessPaymentRequest, payment *models.Payment) (*models.OutboxEvent, error) {
	var eventType string
	var payloadBytes []byte
	var aggregateID string
	var err error

	if payment.Status == models.PaymentStatusCompleted {
		eventType = "PAYMENT_COMPLETED"
		aggregateID = payment.ID.String()
		completedEvent := models.PaymentCompletedEvent{
			EventType:       eventType,
			Status:          string(models.PaymentStatusCompleted),
			PaymentID:       payment.ID.String(),
			OrderNumber:     payment.OrderNumber,
			Amount:          payment.Amount,
			Currency:        payment.Currency,
			PaymentMethod:   payment.PaymentMethod,
			TransactionRef:  payment.TransactionRef,
			CustomerName:    req.CustomerName,
			CustomerEmail:   req.CustomerEmail,
			ShippingAddress: req.ShippingAddress,
			City:            req.City,
			PostalCode:      req.PostalCode,
			Phone:           req.Phone,
			DeliveryMethod:  req.DeliveryMethod,
			UserID:          req.UserID,
			ItemsCount:      req.ItemsCount,
			Timestamp:       payment.UpdatedAt,
		}
		payloadBytes, err = json.Marshal(completedEvent)
	} else {
		eventType = "PAYMENT_FAILED"
		aggregateID = payment.OrderNumber
		failedEvent := models.PaymentFailedEvent{
			EventType:   eventType,
			Status:      string(models.PaymentStatusFailed),
			OrderNumber: payment.OrderNumber,
			Amount:      payment.Amount,
			Reason:      payment.FailureReason,
			ErrorCode:   "PAYMENT_DECLINED",
			Timestamp:   payment.UpdatedAt,
		}
		payloadBytes, err = json.Marshal(failedEvent)
	}
	if err != nil {
		return nil, err
	}

	now := time.Now().UTC()
	initialStatus := "PENDING"
	var lockedAt *time.Time
	if s.producer != nil {
		initialStatus = "PROCESSING"
		lockedAt = &now
	}

	return &models.OutboxEvent{
		ID:            uuid.New(),
		AggregateType: "PAYMENT",
		AggregateID:   aggregateID,
		EventType:     eventType,
		Payload:       string(payloadBytes),
		Status:        initialStatus,
		CreatedAt:     now,
		LockedAt:      lockedAt,
	}, nil
}

func (s *paymentService) publishSingleOutboxEvent(ctx context.Context, ev *models.OutboxEvent) {
	if s.producer == nil || ev == nil {
		return
	}
	var pubErr error
	switch ev.EventType {
	case "PAYMENT_COMPLETED":
		var completedEvent models.PaymentCompletedEvent
		if err := json.Unmarshal([]byte(ev.Payload), &completedEvent); err == nil {
			pubErr = s.producer.PublishPaymentCompleted(ctx, completedEvent)
		} else {
			pubErr = err
		}
	case "PAYMENT_FAILED":
		var failedEvent models.PaymentFailedEvent
		if err := json.Unmarshal([]byte(ev.Payload), &failedEvent); err == nil {
			pubErr = s.producer.PublishPaymentFailed(ctx, failedEvent)
		} else {
			pubErr = err
		}
	case "PAYMENT_REFUNDED":
		var refundedEvent models.PaymentRefundedEvent
		if err := json.Unmarshal([]byte(ev.Payload), &refundedEvent); err == nil {
			pubErr = s.producer.PublishPaymentRefunded(ctx, refundedEvent)
		} else {
			pubErr = err
		}
	default:
		return
	}

	if pubErr == nil {
		now := time.Now().UTC()
		ev.Status = "PUBLISHED"
		ev.ProcessedAt = &now
		ev.LockedAt = nil
		_ = s.repo.UpdateOutboxEvent(ctx, ev)
	} else {
		ev.Status = "PENDING"
		ev.LockedAt = nil
		ev.RetryCount++
		_ = s.repo.UpdateOutboxEvent(ctx, ev)
	}
}

func (s *paymentService) FlushPendingOutbox(ctx context.Context) error {
	if s.producer == nil {
		return nil
	}
	events, err := s.repo.GetPendingOutboxEvents(ctx, 25)
	if err != nil {
		return err
	}

	for i := range events {
		s.publishSingleOutboxEvent(ctx, &events[i])
	}
	return nil
}

func (s *paymentService) outboxDrainerWorker() {
	defer s.workerWg.Done()
	log.Printf("[PaymentService] Outbox drainer worker goroutine started")
	ticker := time.NewTicker(5 * time.Second)
	defer ticker.Stop()

	for {
		select {
		case <-s.stopChan:
			log.Printf("[PaymentService] Outbox drainer worker goroutine stopping")
			return
		case <-ticker.C:
			_ = s.FlushPendingOutbox(context.Background())
		}
	}
}

func (s *paymentService) RefundPayment(ctx context.Context, req models.RefundPaymentRequest) (*models.Payment, error) {
	payment, err := s.repo.FindByOrderNumber(ctx, req.OrderNumber)
	if err != nil {
		return nil, fmt.Errorf("error finding payment: %w", err)
	}
	if payment == nil {
		return nil, errors.New("no payment found for specified order")
	}

	if payment.Status != models.PaymentStatusCompleted && payment.Status != models.PaymentStatusPartiallyRefunded {
		return nil, fmt.Errorf("cannot refund payment with status %s", payment.Status)
	}

	if req.Currency != "" && !strings.EqualFold(strings.TrimSpace(req.Currency), payment.Currency) {
		return nil, fmt.Errorf("refund currency %s does not match payment currency %s", req.Currency, payment.Currency)
	}

	if req.Amount < 0 {
		return nil, errors.New("refund amount must be greater than zero")
	}

	remainingRefundable := math.Round((payment.Amount-payment.RefundedAmount)*100) / 100
	if remainingRefundable <= 0 {
		return nil, errors.New("payment has no remaining refundable balance")
	}

	refundAmount := remainingRefundable
	if req.Amount > 0 {
		refundAmount = math.Round(req.Amount*100) / 100
		if refundAmount > remainingRefundable+1e-6 {
			return nil, fmt.Errorf("refund amount %.2f exceeds remaining refundable balance %.2f", refundAmount, remainingRefundable)
		}
	}

	payment.RefundedAmount = math.Round((payment.RefundedAmount+refundAmount)*100) / 100
	if payment.RefundedAmount >= payment.Amount-1e-6 {
		payment.Status = models.PaymentStatusRefunded
	} else {
		payment.Status = models.PaymentStatusPartiallyRefunded
	}
	payment.UpdatedAt = time.Now().UTC()
	reasonText := strings.TrimSpace(req.Reason)
	if reasonText == "" {
		reasonText = "General"
	}
	payment.FailureReason = fmt.Sprintf("Refunded (%.2f %s): %s", refundAmount, payment.Currency, reasonText)

	refundedEvent := models.PaymentRefundedEvent{
		EventType:   "PAYMENT_REFUNDED",
		Status:      string(payment.Status),
		OrderNumber: payment.OrderNumber,
		Amount:      refundAmount,
		Reason:      reasonText,
		Timestamp:   payment.UpdatedAt,
	}

	payloadBytes, err := json.Marshal(refundedEvent)
	if err != nil {
		return nil, fmt.Errorf("failed to serialize refund outbox event: %w", err)
	}

	now := time.Now().UTC()
	initialStatus := "PENDING"
	var lockedAt *time.Time
	if s.producer != nil {
		initialStatus = "PROCESSING"
		lockedAt = &now
	}

	outboxEvent := &models.OutboxEvent{
		ID:            uuid.New(),
		AggregateType: "PAYMENT",
		AggregateID:   payment.OrderNumber,
		EventType:     "PAYMENT_REFUNDED",
		Payload:       string(payloadBytes),
		Status:        initialStatus,
		CreatedAt:     now,
		LockedAt:      lockedAt,
	}

	if err := s.repo.UpdatePaymentWithOutbox(ctx, payment, outboxEvent); err != nil {
		return nil, fmt.Errorf("failed to persist payment refund and outbox event: %w", err)
	}

	reasonLabel := normalizeRefundReasonLabel(reasonText)
	metrics.PaymentRefundsTotal.WithLabelValues(reasonLabel).Inc()

	s.dispatchAudit(payment.ID, "REFUND", fmt.Sprintf("Refunded %.2f %s for order %s reason: %s", refundAmount, payment.Currency, payment.OrderNumber, reasonText))

	if s.producer != nil {
		s.workerWg.Add(1)
		go func(ev *models.OutboxEvent) {
			defer s.workerWg.Done()
			s.publishSingleOutboxEvent(context.Background(), ev)
		}(outboxEvent)
	}

	return payment, nil
}

func (s *paymentService) GetPaymentByOrder(ctx context.Context, orderNumber string) (*models.Payment, error) {
	return s.repo.FindByOrderNumber(ctx, orderNumber)
}

func (s *paymentService) GetPaymentByID(ctx context.Context, id uuid.UUID) (*models.Payment, error) {
	return s.repo.FindByID(ctx, id)
}

func (s *paymentService) Stop() {
	s.stopOnce.Do(func() {
		close(s.stopChan)
	})
	s.workerWg.Wait()
}

func (s *paymentService) toProcessPaymentResponse(p *models.Payment) *models.ProcessPaymentResponse {
	return &models.ProcessPaymentResponse{
		ID:             p.ID,
		OrderNumber:    p.OrderNumber,
		Amount:         p.Amount,
		Currency:       p.Currency,
		Status:         p.Status,
		PaymentMethod:  p.PaymentMethod,
		TransactionRef: p.TransactionRef,
		FailureReason:  p.FailureReason,
		CreatedAt:      p.CreatedAt,
	}
}
