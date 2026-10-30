package services

import (
	"context"
	"errors"
	"fmt"
	"log"
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
	Stop()
}

type paymentService struct {
	repo      repository.PaymentRepository
	producer  kafka.EventProducer
	auditChan chan *models.PaymentAuditLog
	workerWg  sync.WaitGroup
	stopChan  chan struct{}
}

const (
	auditQueueSize = 500
	auditWorkers   = 3
)

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

	return svc
}

func (s *paymentService) auditWorker(workerID int) {
	defer s.workerWg.Done()
	log.Printf("[PaymentService] Audit worker goroutine #%d started", workerID)

	for {
		select {
		case <-s.stopChan:
			// Drain remaining logs before exiting
			for logItem := range s.auditChan {
				_ = s.repo.CreateAuditLog(context.Background(), logItem)
			}
			log.Printf("[PaymentService] Audit worker goroutine #%d exited", workerID)
			return
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
	case s.auditChan <- auditItem:
		// Dispatched to worker pool
	default:
		// Channel full, handle without blocking payment path
		go func(item *models.PaymentAuditLog) {
			_ = s.repo.CreateAuditLog(context.Background(), item)
		}(auditItem)
	}
}

func (s *paymentService) ProcessPayment(ctx context.Context, req models.ProcessPaymentRequest) (*models.ProcessPaymentResponse, error) {
	timer := metrics.PaymentProcessingDuration.WithLabelValues(req.PaymentMethod)
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

	// 2. Gateway Simulation
	now := time.Now().UTC()
	payment := &models.Payment{
		ID:             uuid.New(),
		OrderNumber:    req.OrderNumber,
		Amount:         req.Amount,
		Currency:       req.Currency,
		PaymentMethod:  req.PaymentMethod,
		IdempotencyKey: req.IdempotencyKey,
		CustomerEmail:  req.CustomerEmail,
		CreatedAt:      now,
		UpdatedAt:      now,
	}
	if payment.Currency == "" {
		payment.Currency = "USD"
	}

	isDeclined := strings.EqualFold(req.PaymentMethod, "CARD_DECLINE") ||
		strings.EqualFold(req.PaymentMethod, "DECLINE") ||
		req.Amount == 9999.99

	if isDeclined {
		payment.Status = models.PaymentStatusFailed
		payment.FailureReason = "Payment declined: simulated insufficient funds or issuer decline"
		payment.TransactionRef = ""
		metrics.PaymentsProcessedTotal.WithLabelValues("FAILED", req.PaymentMethod).Inc()
	} else {
		payment.Status = models.PaymentStatusCompleted
		payment.TransactionRef = fmt.Sprintf("TXN-%s", uuid.New().String()[:8])
		payment.FailureReason = ""
		metrics.PaymentsProcessedTotal.WithLabelValues("COMPLETED", req.PaymentMethod).Inc()
	}

	// 3. Persist in PostgreSQL 18
	if err := s.repo.CreatePayment(ctx, payment); err != nil {
		return nil, fmt.Errorf("failed to persist payment in database: %w", err)
	}

	// 4. Async Audit Log via Goroutines
	s.dispatchAudit(payment.ID, string(payment.Status), fmt.Sprintf("Processed charge for order %s, amount %f %s", payment.OrderNumber, payment.Amount, payment.Currency))

	// 5. Emit Kafka Saga Events
	if s.producer != nil {
		if payment.Status == models.PaymentStatusCompleted {
			completedEvent := models.PaymentCompletedEvent{
				EventType:       "PAYMENT_COMPLETED",
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
			go func() {
				_ = s.producer.PublishPaymentCompleted(context.Background(), completedEvent)
			}()
		} else {
			failedEvent := models.PaymentFailedEvent{
				EventType:   "PAYMENT_FAILED",
				Status:      string(models.PaymentStatusFailed),
				OrderNumber: payment.OrderNumber,
				Amount:      payment.Amount,
				Reason:      payment.FailureReason,
				ErrorCode:   "PAYMENT_DECLINED",
				Timestamp:   payment.UpdatedAt,
			}
			go func() {
				_ = s.producer.PublishPaymentFailed(context.Background(), failedEvent)
			}()
		}
	}

	return s.toProcessPaymentResponse(payment), nil
}

func (s *paymentService) RefundPayment(ctx context.Context, req models.RefundPaymentRequest) (*models.Payment, error) {
	payment, err := s.repo.FindByOrderNumber(ctx, req.OrderNumber)
	if err != nil {
		return nil, fmt.Errorf("error finding payment: %w", err)
	}
	if payment == nil {
		return nil, errors.New("no payment found for specified order")
	}

	if payment.Status != models.PaymentStatusCompleted {
		return nil, fmt.Errorf("cannot refund payment with status %s", payment.Status)
	}

	payment.Status = models.PaymentStatusRefunded
	payment.UpdatedAt = time.Now().UTC()
	payment.FailureReason = fmt.Sprintf("Refunded: %s", req.Reason)

	if err := s.repo.UpdatePayment(ctx, payment); err != nil {
		return nil, fmt.Errorf("failed to update payment record: %w", err)
	}

	reasonTag := req.Reason
	if reasonTag == "" {
		reasonTag = "General"
	}
	metrics.PaymentRefundsTotal.WithLabelValues(reasonTag).Inc()

	s.dispatchAudit(payment.ID, "REFUND", fmt.Sprintf("Refunded order %s reason: %s", payment.OrderNumber, req.Reason))

	if s.producer != nil {
		refundedEvent := models.PaymentRefundedEvent{
			EventType:   "PAYMENT_REFUNDED",
			Status:      string(models.PaymentStatusRefunded),
			OrderNumber: payment.OrderNumber,
			Amount:      payment.Amount,
			Reason:      reasonTag,
			Timestamp:   payment.UpdatedAt,
		}
		go func() {
			_ = s.producer.PublishPaymentRefunded(context.Background(), refundedEvent)
		}()
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
	close(s.stopChan)
	close(s.auditChan)
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
